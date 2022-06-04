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

DbClient client;

static this()
{
    const conf = Config.get;
    client = new DbClient(conf.dbConnString, conf.dbPoolMaxSize);
}

version (DopServerMain) void main(string[] args)
{

    const conf = Config.get;

    auto settings = new HTTPServerSettings(conf.serverHostname);

    const prefix = format("/api/v%s", currentApiLevel);
    auto router = new URLRouter(prefix);

    setupRoute!GetPackage(router, &getPackage);
    setupRoute!GetPackageByName(router, &getPackageByName);
    setupRoute!GetPackageRecipe(router, &getPackageRecipe);

    if (conf.testStopRoute)
        router.post("/stop", &stop);

    auto listener = listenHTTP(settings, router);
    scope (exit)
        listener.stopListening();

    runApplication();
}

void stop(HTTPServerRequest req, HTTPServerResponse res)
{
    res.writeBody("", 200);
    client.finish();
    exitEventLoop();
}

struct PackRow
{
    @ColInd(0)
    int id;

    @ColInd(1)
    string name;
}

PackageResource getPackage(GetPackage req) @safe
{
    return client.connect((scope DbConn db) @safe {
        const pack = db.execRow!PackRow(
            `SELECT "id", "name" FROM "package" WHERE "id" = $1`,
            req.id
        );
        auto vers = db.execScalars!string(
            `SELECT "version" FROM "recipe" WHERE "package_id" = $1`,
            pack.id,
        );
        return PackageResource(pack.id, pack.name, vers);
    });
}

PackageResource getPackageByName(GetPackageByName req) @safe
{
    return client.connect((scope DbConn db) {
        const pack = db.execRow!PackRow(
            `SELECT "id", "name" FROM "package" WHERE "name" = $1`,
            req.name
        );
        auto vers = db.execScalars!string(
            `SELECT "version" FROM "recipe" WHERE "package_id" = $1`,
            pack.id,
        );
        return PackageResource(pack.id, pack.name, vers);
    });
}

struct PackRecipeRow
{
    @ColInd(0)
    int recId;

    @ColInd(1)
    int maintainerId;

    @ColInd(2)
    string ver;

    @ColInd(3)
    string revision;

    @ColInd(4)
    string recipe;

    @ColInd(5)
    SysTime created;
}

PackageRecipeResource getPackageRecipe(GetPackageRecipe req) @safe
{
    return client.connect((scope DbConn db) {
        PackRecipeRow row;
        if (req.revision)
            row = db.execRow!PackRecipeRow(
                `
                    SELECT "id", "maintainer_id", "version", "revision", "recipe", "created"
                    FROM "recipe" WHERE
                        "package_id" = $1 AND
                        "version" = $2 AND
                        "revision" = $3
                `,
                req.packageId, req.ver, req.revision,
            );
        else
            row = db.execRow!PackRecipeRow(
                `
                    SELECT "id", "maintainer_id", "version", "revision", "recipe", "created"
                    FROM "recipe" WHERE
                        "package_id" = $1 AND
                        "version" = $2
                    LIMIT 1
                `,
                req.packageId, req.ver,
            );

        const packName = db.execScalar!string(
            `SELECT "name" FROM "package" WHERE "id" = $1`,
            req.packageId
        );

        auto files = db.execRows!RecipeFile(
            `
                SELECT "id", "name", "size"::bigint FROM "recipe_file"
                WHERE "recipe_id" = $1
            `,
            row.recId,
        );

        return PackageRecipeResource(
            row.recId,
            packName,
            row.ver,
            row.revision,
            row.recipe,
            row.maintainerId,
            row.created.toUTC(),
            files
        );
    });
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
