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
    string reason;

    this(int statusCode, string reason = null, string file = __FILE__, size_t line = __LINE__) @safe
    {
        super(format!"%s: %s%s"(statusCode, httpStatusText(statusCode), reason ? "\n" ~ reason : ""), file, line);
        this.statusCode = statusCode;
        this.reason = reason;
    }
}

T enforceStatus(T)(T condition, int statusCode, string reason = null,
    string file = __FILE__, size_t line = __LINE__) @safe
{
    static assert(is(typeof(!condition)), "condition must cast to bool");
    if (!condition)
        throw new StatusException(statusCode, reason, file, line);
    return condition;
}

noreturn statusError(int statusCode, string reason = null, string file = __FILE__, size_t line = __LINE__) @safe
{
    throw new StatusException(statusCode, reason, file, line);
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

        setupDownloadRoute!DownloadRecipeArchive(router, &downloadRecipeArchive);

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
        enforceStatus(rng.length <= 1, 400, "Multi-part ranges not supported");

        @OrderedCols
        static struct Info
        {
            string pkgName;
            string ver;
            string revision;
            uint totalLength;
        }

        const info = client.connect(db => db.execRow!Info(
                `SELECT package_name, version, revision, length(archive_data) FROM recipe WHERE id = $1`,
                id
        ));
        const totalLength = info.totalLength;

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
        enforceStatus(slice.last >= slice.first, 400, "Invalid range: " ~ req.headers.get("Range"));
        enforceStatus(slice.end <= totalLength, 400, "Invalid range: content bounds exceeded");

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
        statusError(400, "Invalid " ~ paramName ~ " parameter");
    }
    catch (Exception ex)
    {
        statusError(400, "Missing " ~ paramName ~ " parameter");
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

    enforceStatus(header.startsWith("bytes="), 400, "Bad format of range header");
    Rng[] res;
    const parts = header["bytes=".length .. $].split(",");
    foreach (string part; parts)
    {
        part = part.strip();
        const indices = part.split("-");
        if (indices.length != 2 || (!indices[0].length && !indices[1].length))
        {
            statusError(400, "Bad format of range header");
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

HTTPServerRequestDelegateS genericHandler(H)(H handler) @safe
{
    static assert(isSomeFunction!H);
    static assert(isSafe!H);
    static assert(is(typeof(handler(HTTPServerRequest.init, HTTPServerResponse.init)) == void));

    return (scope req, scope resp) @safe {
        try
        {
            logInfo("--> %s %s", req.method, req.requestURI);
            handler(req, resp);
        }
        catch (ResourceNotFoundException ex)
        {
            () @trusted { logError("Not found error: %s", ex.msg); }();
            resp.statusCode = 404;
            resp.writeBody(ex.msg);
        }
        catch (StatusException ex)
        {
            () @trusted { logError("Status error: %s", ex.msg); }();
            resp.statusCode = ex.statusCode;
            resp.writeBody(ex.msg);
        }
        catch (Exception ex)
        {
            () @trusted { logError("Internal error: %s", ex.msg); }();
            resp.statusCode = 500;
            resp.writeBody("Internal Server Error");
        }
        logInfo("<-- %s", resp.statusCode);
    };
}

private void setupRoute(ReqT, H)(URLRouter router, H handler) @safe
{
    static assert(isSomeFunction!H);
    static assert(isSafe!H);
    static assert(is(typeof(handler(ReqT.init)) == ResponseType!ReqT));

    auto routeHandler = genericHandler((scope HTTPServerRequest httpReq, scope HTTPServerResponse httpResp) @safe {
        auto req = adaptRequest!ReqT(httpReq);
        auto resp = handler(req);
        httpResp.writeJsonBody(serializeToJson(resp));
    });

    enum reqAttr = RequestAttr!ReqT;

    static if (reqAttr.method == Method.GET)
        router.get(reqAttr.resource, routeHandler);
    else static if (reqAttr.method == Method.POST)
        router.post(reqAttr.resource, routeHandler);
    else
        static assert(false);
}

private void setupDownloadRoute(ReqT, H)(URLRouter router, H handler) @safe
{
    auto downloadHandler = genericHandler(handler);

    enum reqAttr = RequestAttr!ReqT;

    router.match(HTTPMethod.HEAD, reqAttr.resource, downloadHandler);
    router.match(HTTPMethod.GET, reqAttr.resource, downloadHandler);
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
            try {
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
            catch (ConvException ex)
            {
                throw new StatusException(400, "Invalid parameter: " ~ ident);
            }
            catch (Exception ex)
            {
                throw new StatusException(400, "Missing parameter: " ~ ident);
            }
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

        try
        {
            const value = httpReq.query[queryName];
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
        }
        catch (ConvException ex)
        {
            throw new StatusException(400, "Invalid query parameter: " ~ queryName);
        }
        catch (Exception ex)
        {
            throw new StatusException(400, "Missing query parameter: " ~ queryName);
        }
    }}
    // dfmt on

    return req;
}
