module dopamine.server.app;

import dopamine.server.config;
import dopamine.server.db;
import dopamine.api.attrs;
import dopamine.api.v1;
import dopamine.semver;
import pgd.conn;

import vibe.core.args;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.router;
import vibe.http.server;

import std.base64;
import std.conv;
import std.datetime.systime;
import std.exception;
import std.format;
import std.string;
import std.traits;
import std.typecons;

class StatusException : Exception
{
    int statusCode;
    string statusPhrase;

    this(int statusCode, string statusPhrase = null, string file = __FILE__, size_t line = __LINE__) @safe
    {
        super(format!"Status %s%s"(statusCode, statusPhrase ? ": " ~ statusPhrase : ""), file, line);
        this.statusCode = statusCode;
        this.statusPhrase = statusPhrase;
    }
}

enum currentApiLevel = 1;

version (DopServerMain) void main(string[] args)
{
    auto registry = new DopRegistry();
    auto listener = registry.listen();
    scope (exit)
        listener.stopListening();

    runApplication();
}

class DopRegistry
{
    HTTPServerSettings settings;
    DbClient client;
    URLRouter router;
    string downloadUrlBase;

    this()
    {
        const conf = Config.get;

        client = new DbClient(conf.dbConnString, conf.dbPoolMaxSize);
        settings = new HTTPServerSettings(conf.serverHostname);

        const prefix = format("/api/v%s", currentApiLevel);
        router = new URLRouter(prefix);

        setupRoute!GetPackage(router, &getPackage);
        setupRoute!GetLatestRecipeRevision(router, &getLatestRecipeRevision);
        setupRoute!GetRecipeRevision(router, &getRecipeRevision);
        setupRoute!GetRecipe(router, &getRecipe);
        setupRoute!GetRecipeFiles(router, &getRecipeFiles);

        const protocol = settings.tlsContext ? "https" : "http";
        downloadUrlBase = format!"%s://%s%s/download"(protocol, conf.serverHostname, prefix);

        router.match(HTTPMethod.HEAD, "/recipes/:id/archive", &downloadRecipeArchive);
        router.match(HTTPMethod.GET, "/recipes/:id/:archive", &downloadRecipeArchive);

        if (conf.testStopRoute)
            router.post("/stop", &stop);

        router.get("*", &fallback);
    }

    HTTPListener listen()
    {
        return listenHTTP(settings, router);
    }

    void stop(HTTPServerRequest req, HTTPServerResponse resp)
    {
        resp.writeBody("", 200);
        client.finish();
        exitEventLoop();
    }

    void fallback(HTTPServerRequest req, HTTPServerResponse resp)
    {
        logInfo("fallback for %s", req.requestURI);
    }

    @OrderedCols
    static struct PackRow
    {
        string name;
        int maintainerId;
        SysTime created;

        PackageResource toResource(string[] versions) const @safe
        {
            return PackageResource(name, maintainerId, created.toUTC(), versions);
        }
    }

    PackageResource getPackage(GetPackage req) @safe
    {
        return client.connect((scope DbConn db) @safe {
            const row = db.execRow!PackRow(
                `SELECT "name", "maintainer_id", "created" FROM "package" WHERE "name" = $1`,
                req.name
            );
            auto vers = db.execScalars!string(
                `SELECT DISTINCT "version" FROM "recipe" WHERE "package_name" = $1`,
                row.name,
            );
            // sorting descending order (latest versions first)
            import std.algorithm : sort;

            vers.sort!((a, b) => Semver(a) > Semver(b));
            return row.toResource(vers);
        });
    }

    @OrderedCols
    static struct RecipeRow
    {
        int id;
        int maintainerId;
        SysTime created;
        string ver;
        string revision;
        string recipe;

        RecipeResource toResource() const @safe
        {
            return RecipeResource(
                id, ver, revision, recipe, maintainerId, created.toUTC()
            );
        }
    }

    RecipeResource getLatestRecipeRevision(GetLatestRecipeRevision req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!RecipeRow(
                `
                    SELECT "id", "maintainer_id", "created", "version", "revision", "recipe"
                    FROM "recipe" WHERE
                        "package_name" = $1 AND
                        "version" = $2
                    ORDER BY "created" DESC
                    LIMIT 1
                `,
                req.name, req.ver,
            );
            return row.toResource();
        });
    }

    RecipeResource getRecipeRevision(GetRecipeRevision req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!RecipeRow(
                `
                    SELECT "id", "maintainer_id", "created", "version", "revision", "recipe"
                    FROM "recipe" WHERE
                        "package_name" = $1 AND
                        "version" = $2 AND
                        "revision" = $3
                `,
                req.name, req.ver, req.revision,
            );
            return row.toResource();
        });
    }

    RecipeResource getRecipe(GetRecipe req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!RecipeRow(
                `
                    SELECT "id", "maintainer_id", "created", "version", "revision", "recipe"
                    FROM "recipe" WHERE "id" = $1
                `,
                req.id
            );
            return row.toResource();
        });
    }

    const(RecipeFile)[] getRecipeFiles(GetRecipeFiles req) @safe
    {
        return client.connect((scope DbConn db) {
            return db.execRows!RecipeFile(
                `SELECT "name", "size" FROM "recipe_file" WHERE "recipe_id" = $1`, req.id,
            );
        });
    }

    void downloadRecipeArchive(scope HTTPServerRequest req, scope HTTPServerResponse resp) @safe
    {
        const id = convParam!int(req, "id");

        auto rng = parseRangeHeader(req);
        if (rng.length > 1)
            throw new StatusException(400, "Bad Request: multipart ranges are not supported");

        const totalLength = client.connect(db =>
                db.execScalar!uint(
                    `SELECT length(archive_data) FROM recipe WHERE id = $1`, id
                )
        );

        @OrderedCols
        static struct Info
        {
            string pkgName;
            string ver;
            string revision;
        }

        const info = client.connect(db => db.execRow!Info(
                `SELECT package_name, version, revision FROM recipe WHERE id = $1`,
                id
        ));
        resp.headers["Content-Disposition"] = format!"attachment; filename=%s-%s-%s.tar.xz"(
            info.pkgName, info.ver, info.revision
        );

        if (reqWantDigestSha256(req))
        {
            const sha = client.connect(db => db.execScalar!(ubyte[32])(
                    `SELECT sha256(archive_data) FROM recipe WHERE id = $1`,
                    id,
            ));
            resp.headers["Digest"] = () @trusted {
                return assumeUnique("sha-256=" ~ Base64.encode(sha));
            }();
        }

        resp.headers["Accept-Ranges"] = "bytes";

        const slice = rng.length ?
            rng[0].slice(totalLength) : ContentSlice(0, totalLength - 1, totalLength);

        if (slice.last < slice.first)
            throw new StatusException(400, "Invalid range: " ~ req.headers["range"]);
        if (slice.end > totalLength)
            throw new StatusException(400, "Invalid range: exceeds content bounds");

        resp.headers["Content-Length"] = slice.sliceLength.to!string;
        if (rng.length)
            resp.headers["Content-Range"] = format!"bytes %s-%s/%s"(slice.first, slice.last, totalLength);

        if (req.method == HTTPMethod.HEAD)
        {
            resp.writeVoidBody();
            return;
        }

        const(ubyte)[] data;
        if (rng.length)
        {
            data = client.connect((scope db) {
                // substring index is one based
                return db.execScalar!(const(ubyte)[])(
                    `SELECT substring(archive_data FROM $1 FOR $2) FROM recipe WHERE id = $3`,
                    slice.first + 1, slice.sliceLength, id,
                );
            });
            resp.statusCode = 206;
        }
        else
        {
            data = client.connect((scope db) {
                return db.execScalar!(const(ubyte)[])(
                    `SELECT archive_data FROM recipe WHERE id = $1`, id,
                );
            });
        }
        enforce(slice.sliceLength == data.length, "No match of data length and content length");

        resp.writeBody(data);
    }
}

T convParam(T)(scope HTTPServerRequest req, string paramName) @safe
{
    try
    {
        return req.params[paramName].to!T;
    }
    catch (ConvException ex)
    {
        throw new StatusException(400, "Bad Request: invalid " ~ paramName ~ " parameter");
    }
}

bool reqWantDigestSha256(scope HTTPServerRequest req) @safe
{
    return req.headers.get("want-digest") == "sha-256";
}

struct Rng
{
    enum Mode
    {
        normal,
        suffix,
    }

    Mode mode;
    uint first;
    uint last;

    ContentSlice slice(uint totalLength) const @safe
    {
        final switch (mode)
        {
        case Mode.normal:
            return ContentSlice(
                first, last ? last : totalLength - 1, totalLength
            );
        case Mode.suffix:
            return ContentSlice(
                totalLength - last, totalLength - 1, totalLength
            );
        }
    }
}

struct ContentSlice
{
    uint first;
    uint last;
    uint totalLength;

    @property uint end() const @safe
    {
        return last + 1;
    }

    @property uint sliceLength() const @safe
    {
        return last - first + 1;
    }
}

Rng[] parseRangeHeader(scope HTTPServerRequest req) @safe
{
    auto header = req.headers.get("Range").strip();
    if (!header.length)
        return [];

    logInfo("range header: %s", header);

    if (!header.startsWith("bytes="))
    {
        throw new StatusException(
            400,
            "Bad request: Bad format of range header",
        );
    }
    Rng[] res;
    const parts = header["bytes=".length .. $].split(",");
    foreach (string part; parts)
    {
        part = part.strip();
        const indices = part.split("-");
        if (indices.length != 2 || (!indices[0].length && !indices[1].length))
        {
            throw new StatusException(
                400,
                "Bad request: Bad format of range header",
            );
        }
        Rng rng;
        if (indices[0].length)
            rng.first = indices[0].to!uint;
        else
            rng.mode = Rng.Mode.suffix;

        if (indices[1].length)
            rng.last = indices[1].to!uint;
        res ~= rng;
    }
    return res;
}

void setupRoute(ReqT, H)(URLRouter router, H handler)
{
    static assert(isSomeFunction!H);
    static assert(isSafe!H);
    static assert(is(typeof(handler(ReqT.init))));
    static assert(is(ReturnType!H == ResponseType!ReqT));

    HTTPServerRequestDelegateS dg = (scope httpReq, httpResp) @safe {
        try
        {
            auto req = adaptRequest!ReqT(httpReq);
            () @trusted { logInfo("Parsed query %s", req); }();
            try
            {
                auto resp = handler(req);
                () @trusted { logInfo("Response %s", resp); }();
                httpResp.writeJsonBody(serializeToJson(resp));
            }
            catch (ResourceNotFoundException ex)
            {
                () @trusted { logInfo("Not found error %s", ex.msg); }();
                httpResp.statusCode = 404;
            }
            catch (StatusException ex)
            {
                () @trusted { logInfo("Status error %s", ex.msg); }();
                httpResp.statusCode = ex.statusCode;
                if (ex.statusPhrase)
                    httpResp.statusPhrase = ex.statusPhrase;
            }
            catch (Exception ex)
            {
                () @trusted { logError("Internal error: %s", ex.msg); }();
                httpResp.statusCode = 500;
            }
        }
        catch (Exception)
        {
            httpResp.statusCode = 400;
        }
    };

    enum reqAttr = RequestAttr!ReqT;

    static if (reqAttr.method == Method.GET)
        router.get(reqAttr.resource, dg);
    else static if (reqAttr.method == Method.POST)
        router.post(reqAttr.resource, dg);
    else
        static assert(false);
}

private ReqT adaptRequest(ReqT)(HTTPServerRequest httpReq) if (isRequest!ReqT)
{
    enum reqAttr = RequestAttr!ReqT;
    static assert(
        reqAttr.resource.length > 1 && reqAttr.resource[0] == '/',
        "Invalid resource URL: " ~ reqAttr.resource ~ " (must start by '/')"
    );

    enum resourceParts = split(reqAttr.resource[1 .. $], '/');

    ReqT req;

    // dfmt off
    static foreach(enum part; resourceParts)
    {{
        enum isParam = part.length > 0 && part[0] == ':';
        static if (isParam)
        {
            enum ident = part[1 .. $];
            const param = httpReq.params[ident];

            alias syms = getSymbolsByUDA!(ReqT, ident);
            static if (syms.length)
            {
                __traits(getMember, req, __traits(identifier, syms[0])) =
                    param.to!(typeof(__traits(getMember, req, __traits(identifier, syms[0]))));
            }
            else static if (__traits(hasMember, req, ident))
            {
                __traits(getMember, req, ident) = param.to!(typeof(__traits(getMember, req, ident)));
            }
            else static assert(false, "Could not find a " ~ ident ~ " parameter value in " ~ ReqT.stringof);
        }
    }}
    // dfmt on

    alias queryParams = getSymbolsByUDA!(ReqT, Query);

    // dfmt off
    static foreach (alias sym; queryParams)
    {{
        // determine if @Query is used instead of @Query() or @Query("name")
        // (@Query misses this to get name)
        static if (is(getUDAs!(sym, Query)[0] == Query))
        {
            enum string symName = null;
        }
        else
        {
            enum symName = getUDAs!(sym, Query)[0].name;
        }

        alias T = Unqual!(typeof(__traits(getMember, req, __traits(identifier, sym))));

        enum queryName = symName ? symName : __traits(identifier, sym);

        const value = httpReq.query.get(queryName);

        static if (is(T == bool))
        {
            // empty string means true
            if (value == "")
                __traits(getMember, req, __traits(identifier,  sym)) = true;
            else
                __traits(getMember, req, __traits(identifier,  sym)) = value.to!bool;
        }
        else
        {
            __traits(getMember, req, __traits(identifier,  sym)) = value.to!T;
        }
    }}
    // dfmt on

    return req;
}
