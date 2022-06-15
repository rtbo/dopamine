module dopamine.server.app;

import dopamine.server.config;
import dopamine.server.db;
import dopamine.api.attrs;
import dopamine.api.v1;
import dopamine.semver;
import jwt;
import pgd.conn;

import squiz_box;

import vibe.core.args;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.router;
import vibe.http.server;

import std.base64;
import std.conv;
import std.datetime.systime;
import std.digest.sha;
import std.exception;
import std.format;
import std.range;
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

        setupRoute!PostRecipe(router, &postRecipe);
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

    PackageResource createPackageIfNotExist(scope DbConn db, int userId, string packName, out bool newPkg) @safe
    {
        auto prows = db.execRows!PackRow(
            `SELECT name, maintainer_id, created FROM package WHERE name = $1`, packName
        );
        string[] vers;
        newPkg = prows.length == 0;
        if (prows.length == 0)
        {
            prows = db.execRows!PackRow(
                `
                    INSERT INTO package (name, maintainer_id, created)
                    VALUES ($1, $2, CURRENT_TIMESTAMP)
                    RETURNING name, maintainer_id, created
                `,
                packName, userId
            );
        }
        else
        {
            import std.algorithm : sort;

            vers = db.execScalars!string(
                `SELECT version FROM recipe WHERE package_name = $1`, packName
            );
            vers.sort!((a, b) => Semver(a) > Semver(b));
        }
        return prows[0].toResource(vers);
    }

    RecipeFile[] checkAndReadRecipeArchive(const(ubyte)[] archiveData,
        const(ubyte)[] archiveSha256,
        out string recipe) @trusted
    {
        enum szLimit = 1 * 1024 * 1024;

        enforceStatus(
            archiveData.length <= szLimit, 400,
            "Recipe archive is too big. Ensure to not leave unneeded data."
        );

        const sha256 = sha256Of(archiveData);
        enforceStatus(
            sha256[] == archiveSha256, 400, "Could not verify archive integrity (invalid SHA256 checksum)"
        );

        RecipeFile[] files;
        auto entries = only(archiveData)
            .decompressXz()
            .readTarArchive();

        bool seenRecipe;
        foreach (e; entries)
        {
            enforceStatus(!e.isBomb(10 * szLimit), 400, "Archive bomb detected!");

            if (e.path == "dopamine.lua")
            {
                enforceStatus(e.size <= szLimit, 400, "dopamine.lua file is too big!");
                recipe = cast(string) e.byChunk().join().idup;
                seenRecipe = true;
            }
            files ~= RecipeFile(e.path, cast(uint) e.size);
        }
        enforceStatus(
            seenRecipe, 400, "Recipe archive do not contain dopamine.lua file"
        );
        return files;
    }

    NewRecipeResp postRecipe(int userId, PostRecipe req) @safe
    {
        // FIXME: package name rules
        import std.stdio;
        enforceStatus(
            Semver.isValid(req.ver), 400, "Invalid package version (not Semver compliant)"
        );
        enforceStatus(
            req.revision.length, 400, "Invalid package revision"
        );

        const archiveSha256 = Base64.decode(req.archiveSha256);
        const archive = Base64.decode(req.archive);

        string recipe;
        auto files = checkAndReadRecipeArchive(archive, archiveSha256, recipe);

        return client.transac((scope db) @safe {
            bool newPkg;
            auto pkg = createPackageIfNotExist(db, userId, req.name, newPkg);
            const recExists = db.execScalar!bool(
                `
                    SELECT count(id) <> 0 FROM recipe
                    WHERE package_name = $1 AND version = $2 AND revision = $3
                `,
                req.name, req.ver, req.revision
            );
            enforceStatus(
                !recExists, 400,
                format!"recipe %s/%s/%s already exists!"(req.name, req.ver, req.revision)
            );

            const recipeRow = db.execRow!RecipeRow(
                `
                    INSERT INTO recipe (
                        package_name,
                        maintainer_id,
                        created,
                        version,
                        revision,
                        recipe,
                        archive_data
                    ) VALUES (
                        $1, $2, CURRENT_TIMESTAMP, $3, $4, $5, $6
                    )
                    RETURNING
                        id,
                        maintainer_id,
                        created,
                        version,
                        revision,
                        recipe
                `, req.name, userId, req.ver, req.revision, recipe, archive
            );

            const doubleCheck = db.execScalar!(const(ubyte)[])(
                `SELECT digest(archive_data, 'sha256') FROM recipe WHERE id = $1`, recipeRow.id
            );
            enforce(doubleCheck == archiveSha256, "Could not verify archive integrity after insert");

            foreach (f; files)
                db.exec(
                    `INSERT INTO recipe_file (recipe_id, name, size) VALUES ($1, $2, $3)`,
                    recipeRow.id, f.name, f.size
                );
            return NewRecipeResp(
                newPkg, pkg, recipeRow.toResource()
            );
        });
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
        logInfo("--> %s %s", req.method, req.requestURI);
        try
        {
            handler(req, resp);
        }
        catch (ResourceNotFoundException ex)
        {
            () @trusted { logError("Not found error: %s", ex); }();
            resp.statusCode = 404;
            resp.writeBody(ex.msg);
        }
        catch (StatusException ex)
        {
            () @trusted { logError("Status error: %s", ex); }();
            resp.statusCode = ex.statusCode;
            resp.writeBody(ex.msg);
        }
        catch (Exception ex)
        {
            () @trusted { logError("Internal error: %s", ex); }();
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

    enum requiresAuth = hasUDA!(ReqT, RequiresAuth);
    static if (requiresAuth)
    {
        static assert(is(typeof(handler(1, ReqT.init)) == ResponseType!ReqT));
    }
    else
    {
        static assert(is(typeof(handler(ReqT.init)) == ResponseType!ReqT));
    }

    auto routeHandler = genericHandler((scope HTTPServerRequest httpReq, scope HTTPServerResponse httpResp) @safe {
        static if (requiresAuth)
        {
            const userId = enforceAuth(httpReq);
        }
        auto req = adaptRequest!ReqT(httpReq);
        static if (requiresAuth)
        {
            auto resp = handler(userId, req);
        }
        else
        {
            auto resp = handler(req);
        }
        httpResp.writeJsonBody(serializeToJson(resp));
    });

    enum reqAttr = RequestAttr!ReqT;

    static if (reqAttr.method == Method.GET)
    {
        router.get(reqAttr.resource, routeHandler);
    }
    else static if (reqAttr.method == Method.POST)
    {
        router.post(reqAttr.resource, routeHandler);
    }
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

private int enforceAuth(scope HTTPServerRequest req)
{
    const head = enforceStatus(
        req.headers.get("authorization"), 401, "Authorization required"
    );
    const bearer = "bearer ";
    enforceStatus(
        head.length > bearer.length && head[0 .. bearer.length].toLower() == bearer,
        400, "Ill-formed authorization header"
    );
    const jwt = Jwt(head[bearer.length .. $].strip());
    enforceStatus(
        jwt.isToken,
        400, "Ill-formed authorization header"
    );
    return enforceJwtValid(jwt);
}

private int enforceJwtValid(Jwt jwt)
{
    const config = Config.get;
    try
    {
        enforceStatus(
            jwt.verify(config.serverJwtSecret),
            403, "Invalid or expired token");
    }
    catch(Exception ex)
    {
        statusError(400, "Invalid authorization header");
    }
    return jwt.payload["sub"].get!int;
}

private ReqT adaptRequest(ReqT)(scope HTTPServerRequest httpReq) if (isRequest!ReqT)
{
    enum reqAttr = RequestAttr!ReqT;
    static if (reqAttr.method == Method.GET)
        return adaptGetRequest!ReqT(httpReq);
    else static if (reqAttr.method == Method.POST)
        return adaptPostRequest!ReqT(httpReq);
    else
        static assert(false, "unimplemented method: " ~ reqAttr.method.stringof);
}

private ReqT adaptPostRequest(ReqT)(scope HTTPServerRequest httpReq) if (isRequest!ReqT)
{
    return deserializeJson!ReqT(httpReq.json);
}

private ReqT adaptGetRequest(ReqT)(scope HTTPServerRequest httpReq) if (isRequest!ReqT)
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
