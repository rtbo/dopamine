module dopamine.server.app;

import dopamine.server.config;
import dopamine.server.db;
import dopamine.api.attrs;
import dopamine.api.v1;

import vibe.core.args;
import vibe.core.core;
import vibe.http.router;
import vibe.http.server;

import std.conv;
import std.format;
import std.string;

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

    auto listener = listenHTTP(settings, router);
    scope (exit)
        listener.stopListening();

    runApplication();
}

PackageResource getPackage(GetPackage req)
{
    static struct PackRow
    {
        string id;
        string name;
    }

    return client.connect((scope DbConn db) {
        const pack = db.execRow!PackRow(
            `SELECT "id", "name" FROM "packages" WHERE "id" = $1`,
            req.id
        );
        auto vers = db.execScalars!string(
            `SELECT "version" FROM "recipe" WHERE "package_id" = $1`,
            pack.id,
        );
        return PackageResource(pack.id, pack.name, vers);
    });
}

template RouteHandler(ReqT) if (isRequest!ReqT)
{
    alias RouteHandler = @safe ResponseType!ReqT delegate(ReqT req);
}

void setupRoute(ReqT)(URLRouter router, RouteHandler!ReqT handler)
{
    HTTPServerRequestDelegateS dg = (scope httpReq, httpResp) @safe
    {
        auto req = adaptRequest!ReqT(httpReq);
        auto resp = handler(req);
        req.writeJsonBody(serializeToJson(resp));
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
                __traits(getMember, req, __traits(identifier, syms[0])) = param;
            }
            else static if (__traits(hasMember, req, ident))
            {
                __traits(getMember, req, ident) = param;
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
}


