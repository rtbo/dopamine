module dopamine.registry.utils;

import dopamine.registry.config;
import dopamine.registry.auth;

import dopamine.api.attrs;

import jwt;

import pgd.conn;

import vibe.core.log;
import vibe.data.json;
import vibe.http.router;
import vibe.http.server;

import std.algorithm;
import std.conv;
import std.format;
import std.json;
import std.string;
import std.traits;

class StatusException : Exception
{
    int statusCode;
    string reason;

    this(int statusCode, lazy string reason = null, string file = __FILE__, size_t line = __LINE__) @safe
    {
        super(format!"%s: %s%s"(statusCode, httpStatusText(statusCode), reason ? "\n" ~ reason : ""), file, line);
        this.statusCode = statusCode;
        this.reason = reason;
    }
}

T enforceStatus(T)(T condition, int statusCode, lazy string reason = null,
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

T enforceProp(T)(Json json, string prop) @safe
{
    auto res = json[prop];
    const t = res.type;
    enforceStatus(t != Json.Type.undefined, 400, format!`missing JSON property "%s"`(prop));
    enforceStatus(
        t == Json.typeId!T,
        400,
        format!`wrong type of JSON property "%s". Expected %s, got %s`(prop, T.stringof, t)
    );
    return res.get!T;
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
        catch (JSONException ex)
        {
            () @trusted { logError("JSON error: %s", ex); }();
            if (ex.msg.canFind("Got JSON of type undefined"))
            {
                resp.statusCode = 400;
                resp.writeBody(ex.msg);
            }
            else
            {
                resp.statusCode = 500;
                () @trusted { resp.writeBody(ex.toString()); }();
            }
        }
        catch (Exception ex)
        {
            () @trusted { logError("Internal error: %s", ex); }();
            resp.statusCode = 500;
            () @trusted { resp.writeBody(ex.toString()); }();
        }
        logInfo("<-- %s", resp.statusCode);
    };
}

void setupRoute(ReqT, H)(URLRouter router, H handler) @safe
{
    static assert(isSomeFunction!H);
    static assert(isSafe!H);

    enum requiresAuth = hasUDA!(ReqT, RequiresAuth);
    static if (requiresAuth)
    {
        static assert(is(typeof(handler(UserInfo.init, ReqT.init)) == ResponseType!ReqT));
    }
    else
    {
        static assert(is(typeof(handler(ReqT.init)) == ResponseType!ReqT));
    }

    auto routeHandler = genericHandler((scope HTTPServerRequest httpReq, scope HTTPServerResponse httpResp) @safe {
        static if (requiresAuth)
        {
            const userInfo = enforceAuth(httpReq);
        }
        auto req = adaptRequest!ReqT(httpReq);
        static if (requiresAuth)
        {
            auto resp = handler(userInfo, req);
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

void setupDownloadRoute(ReqT, H)(URLRouter router, H handler) @safe
{
    auto downloadHandler = genericHandler(handler);

    enum reqAttr = RequestAttr!ReqT;

    router.match(HTTPMethod.HEAD, reqAttr.resource, downloadHandler);
    router.match(HTTPMethod.GET, reqAttr.resource, downloadHandler);
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

private ReqT adaptPostRequest(ReqT)(scope HTTPServerRequest httpReq)
        if (isRequest!ReqT)
{
    return deserializeJson!ReqT(httpReq.json);
}

private ReqT adaptGetRequest(ReqT)(scope HTTPServerRequest httpReq)
        if (isRequest!ReqT)
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
