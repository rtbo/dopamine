module dopamine.server.app;

import dopamine.server.config;
import dopamine.server.db;
import dopamine.api.attrs;
import dopamine.api.v1;
import pgd.conn;

import vibe.core.args;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.router;
import vibe.http.server;

import std.conv;
import std.datetime.systime;
import std.format;
import std.string;
import std.traits;

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
        setupRoute!GetRecipeArchive(router, &getRecipeArchive);

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

    static struct PackRow
    {
        @ColInd(0) string name;
        @ColInd(1) int maintainerId;
        @ColInd(2) SysTime created;

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
            return row.toResource(vers);
        });
    }

    static struct RecipeRow
    {
        @ColInd(0) int id;
        @ColInd(1) int maintainerId;
        @ColInd(2) SysTime created;
        @ColInd(3) string ver;
        @ColInd(4) string revision;
        @ColInd(5) string recipe;

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
                `
                    SELECT "name", "size"::bigint FROM "recipe_file"
                    WHERE "recipe_id" = $1
                `,
                req.id,
            );
        });
    }

    static struct DownloadRow
    {
        string filename;
        ulong size;
        string sha1;

        DownloadInfo toResource(string url) const @safe
        {
            return DownloadInfo(filename, cast(size_t) size, sha1, url);
        }
    }

    DownloadInfo getRecipeArchive(GetRecipeArchive req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!DownloadRow(
                `
                    SELECT
                        "archivename",
                        LENGTH("archivedata") AS "size",
                        ENCODE(DIGEST("archivedata", 'sha1'), 'hex') AS "sha1"
                    FROM "recipe" WHERE "id" = $1
                `,
                req.id,
            );
            return row.toResource("TODO");
        });
    }
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
