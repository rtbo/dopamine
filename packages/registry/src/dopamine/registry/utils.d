module dopamine.registry.utils;

import dopamine.registry.config;
import dopamine.registry.auth;

import dopamine.api.attrs;

import jwt;

import pgd.conn;
import pgd.maybe;

import vibe.core.log;
import vibe.core.stream;
import vibe.data.json;
import vibe.http.router;
import vibe.http.server;

import std.algorithm;
import std.conv;
import std.format;
import std.json;
import std.string;
import std.traits;

T enforceStatus(T)(T condition, int statusCode, lazy string reason = null,
    string file = __FILE__, size_t line = __LINE__) @safe
{
    static assert(is(typeof(!condition)), "condition must cast to bool");
    if (!condition)
        throw new HTTPStatusException(statusCode, reason, file, line);
    return condition;
}

noreturn statusError(int statusCode, string reason = null, string file = __FILE__, size_t line = __LINE__) @safe
{
    throw new HTTPStatusException(statusCode, reason, file, line);
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
            statusError(400, "Bad format of range header");

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
        catch (HTTPStatusException ex)
        {
            () @trusted { logError("Status error: %s", ex); }();
            resp.statusCode = ex.status;
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
            const userInfo = enforceUserAuth(httpReq);
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

package(dopamine.registry) ReqT adaptRequest(ReqT)(scope HTTPServerRequest httpReq) if (isRequest!ReqT)
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
                throw new HTTPStatusException(400, "Invalid parameter: " ~ ident);
            }
            catch (Exception ex)
            {
                throw new HTTPStatusException(400, "Missing parameter: " ~ ident);
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
            static if (is(T == bool))
            {
                const value = httpReq.query.get(queryName, "false");
                // empty string means true
                if (value == "")
                    __traits(getMember, req, __traits(identifier,  sym)) = true;
                else
                    __traits(getMember, req, __traits(identifier,  sym)) = value.to!bool;
            }
            else static if (is(T == string))
            {
                const value = httpReq.query.get(queryName, null);
                __traits(getMember, req, __traits(identifier,  sym)) = value;
            }
            else
            {
                enum omitIfInit = hasUDA!(sym, OmitIfInit);
                const value = httpReq.query.get(queryName, null);
                if (!omitIfInit && !value)
                    throw new HTTPStatusException(400, "Missing query parameter: " ~ queryName);
                if (value)
                    __traits(getMember, req, __traits(identifier,  sym)) = value.to!T;
            }
        }
        catch (ConvException ex)
        {
            throw new HTTPStatusException(400, "Invalid query parameter: " ~ queryName);
        }
    }}
    // dfmt on

    return req;
}

Json enforceAuth(scope HTTPServerRequest req) @safe
{
    const head = enforceStatus(
        req.headers.get("authorization"), 401, "Authorization required"
    );

    return extractAuth(head);
}

MayBe!Json checkAuth(scope HTTPServerRequest req) @safe
{
    const head = req.headers.get("authorization");

    if (!head)
        return mayBe!Json();

    return mayBe(extractAuth(head));
}

private Json extractAuth(string head) @safe
{
    const bearer = "bearer ";
    enforceStatus(
        head.length > bearer.length && head[0 .. bearer.length].toLower() == bearer,
        400, "Ill-formed authorization header"
    );
    try
    {
        import std.typecons : Yes;

        const conf = Config.get;
        const jwt = Jwt.verify(
            head[bearer.length .. $].strip(),
            conf.registryJwtSecret,
            Jwt.VerifOpts(Yes.checkExpired, [conf.registryHostname]),
        );
        return jwt.payload;
    }
    catch (JwtException ex)
    {
        final switch (ex.cause)
        {
        case JwtVerifFailure.structure:
            statusError(400, format!"Ill-formed authorization header: %s"(ex.msg));
        case JwtVerifFailure.payload:
            // 500 because it is checked after signature
            statusError(500, format!"Improper field in authorization header payload: %s"(ex.msg));
        case JwtVerifFailure.expired:
            statusError(403, "Expired authorization token");
        case JwtVerifFailure.signature:
            statusError(403, "Invalid authorization token");
        }
    }
}

auto streamByteRange(I)(I input, size_t bufSize) if(isInputStream!I)
{
    return StreamByteRange!I(input, bufSize);
}

struct StreamByteRange(I)
if (isInputStream!I)
{
    private I _input;
    private ubyte[] _buf;
    private ubyte[] _chunk;

    this(I input, size_t bufSize)
    {
        _buf = new ubyte[bufSize];
        _input = input;
        if (!_input.empty)
            prime();
    }

    private void prime()
    {
        const sz = min(_input.leastSize, _buf.length);
        _input.read(_buf[0 .. sz]);
        _chunk = _buf[0 .. sz];
    }

    @property bool empty()
    {
        return _input.empty && _chunk.length == 0;
    }

    @property const(ubyte)[] front()
    {
        return _chunk;
    }

    void popFront()
    {
        _chunk = null;
        if (!_input.empty)
            prime();
    }
}
