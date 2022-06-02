module dopamine.registry;

import dopamine.api.attrs;
import dopamine.login;

import vibe.data.json;

@safe:

/// Exception thrown when constructing a registry with invalid registry host
class InvalidRegistryHostException : Exception
{
    /// The host value that triggered the exception
    string host;
    /// The reason why the host is invalid
    string reason;

    this(string host, string reason, string file = __FILE__, size_t line = __LINE__)
    {
        import std.format : format;

        this.host = host;
        this.reason = reason;
        super(format(
                "Host \"%s\" is not valid: %s.",
                host, reason
        ), file, line);
    }
}

/// An error thrown when attempting to perform a request requiring authentication
/// without login information.
class AuthRequiredException : Exception
{
    /// The URL of the request
    string url;

    this(string url, string file = __FILE__, size_t line = __LINE__)
    {
        import std.format : format;

        this.url = url;
        super(format(
                "Request \"%s\" requires authentication. You might get one from the " ~ defaultRegistry ~ ".",
                url
        ), file, line);
    }
}

/// An error that correspond to a server seemingly down
class ServerDownException : Exception
{
    /// The URL of the server
    string host;
    /// A message from Curl backend
    string reason;

    this(string host, string reason, string file = __FILE__, size_t line = __LINE__)
    {
        import std.format : format;

        this.host = host;
        this.reason = reason;
        super(format("Server %s appears to be down: %s", host, reason), file, line);
    }
}

/// An error that correspond to a server response code >= 400
class ErrorResponseException : Exception
{
    /// The HTTP code of the response
    int code;
    /// A phrase that maps with the status code (e.g. "OK" or "Not Found")
    string reason;
    /// A message that might be given by the server in case of error.
    string error;

    this(int code, string reason, string error, string file = __FILE__, size_t line = __LINE__)
    {
        import std.format : format;

        this.code = code;
        this.reason = reason;
        this.error = error;
        super(format("Server response is %s - %s: %s", code, reason, error), file, line);
    }
}

/// Response returned by the Registry
struct Response(T)
{
    static if (!is(T == void))
    {
        /// The data returned in the response
        private T _payload;
    }
    /// The HTTP code of the response
    int code;
    /// A phrase that maps with the status code (e.g. "OK" or "Not Found")
    string reason;
    /// A message that might be given by the server in case of error.
    string error;

    /// Checks whether the response is valid and payload can be used.
    bool opCast(T : bool)() const
    {
        return code < 400;
    }

    static if (!is(T == void))
    {
        /// Get the payload, or throw ErrorResponseException
        @property inout(T) payload() inout
        {
            if (code >= 400)
            {
                throw new ErrorResponseException(code, reason, error);
            }
            return _payload;
        }
    }
    else
    {
        /// Get a response without payload
        @property Response!void toVoid()
        {
            return Response!void(code, reason, error);
        }
    }
}

private template mapResp(alias pred)
{
    auto mapResp(T)(Response!T resp)
    {
        alias U = typeof(pred(T.init));
        if (resp)
        {
            return Response!U(pred(resp.payload), resp.code, resp.reason, resp.error);
        }
        else
        {
            return Response!U(U.init, resp.code, resp.reason, resp.error);
        }
    }
}

/// The URL of default registry the client connects to.
enum defaultRegistry = "http://localhost:3000";

/// Client interface to the registry.
class Registry
{
    string _host;
    LoginKey _key;

    this(LoginKey key = LoginKey.init)
    {
        import std.process : environment;

        _host = checkHost(environment.get("DOP_REGISTRY", defaultRegistry));
        _key = key;
    }

    this(string host, LoginKey key = LoginKey.init)
    {
        _host = checkHost(host);
        _key = key;
    }

    @property string host() const
    {
        return _host;
    }

    @property LoginKey key() const
    {
        return _key;
    }

    Response!(ResponseType!ReqT) sendRequest(ReqT)(auto ref const ReqT req) if (isRequest!ReqT)
    {
        import std.conv : to;
        import std.traits : hasUDA;

        enum reqAttr = RequestAttr!ReqT;
        enum method = reqAttr.method;
        enum requiresAuth = hasUDA!(ReqT, RequiresAuth);

        static if (requiresAuth)
        {
            enforce(_key, new AuthRequiredException(reqAttr.url));
        }

        static assert(reqAttr.apiLevel >= 1, "Invalid API Level: " ~ reqAttr.apiLevel.to!string);

        const resource = requestResource(req);
        auto res = rawReq(method, _key.key, host, resource, null, null);

        static if (hasResponse!ReqT)
        {
            alias ResT = ResponseType!ReqT;
            return res.mapResp!(raw => toJson(raw).deserializeJson!(ResT)());
        }
        else
        {
            return res.toVoid;
        }
    }
}

private string checkHost(string host)
{
    import std.exception : enforce;
    import std.string : endsWith, startsWith;

    enforce(
        host.startsWith("http://"),
        new InvalidRegistryHostException(host, "Only http:// protocol is supported")
    );
    enforce(
        !host.endsWith("/"),
        new InvalidRegistryHostException(host, "The final '/' must be removed")
    );
    return host;
}

private string requestResource(ReqT)(auto ref const ReqT req) if (isRequest!ReqT)
{
    import std.array : split;
    import std.conv : to;
    import std.format : format;
    import std.traits : getUDAs, getSymbolsByUDA, Unqual;
    import std.uri : encodeComponent;

    enum reqAttr = RequestAttr!ReqT;
    static assert(
        reqAttr.resource.length > 1 && reqAttr.resource[0] == '/',
        "Invalid resource URL: " ~ reqAttr.resource ~ " (must start by '/')"
    );

    enum prefix = format("/api/v%s", reqAttr.apiLevel);
    enum resourceParts = split(reqAttr.resource[1 .. $], '/');

    string resource = prefix;

    // dfmt off
    static foreach(enum part; resourceParts)
    {{
        enum isParam = part.length > 0 && part[0] == ':';
        enum leftover = isParam ? part[1 .. $] : part;
        static assert(leftover.length, "Invalid empty resource: " ~ reqAttr.resource);

        resource ~= "/";

        static if (isParam)
        {
            alias syms = getSymbolsByUDA!(ReqT, leftover);
            static if (syms.length)
            {
                const value = __traits(getMember, req, __traits(identifier, syms[0]));
            }
            else static if (__traits(hasMember, req, leftover))
            {
                const value = __traits(getMember, req, leftover);
            }
            else static assert(false, "Could not find a " ~ leftover ~ " parameter value in " ~ ReqT.stringof);

            resource ~= encodeComponent(value.to!string);
        }
        else
        {
            resource ~= leftover;
        }
    }}
    // dfmt on

    alias queryParams = getSymbolsByUDA!(ReqT, Query);

    static if (queryParams.length)
    {
        static assert(reqAttr.method == Method.GET, "Query parameters are only allowed in GET requests");

        string sep = "?";

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

            enum paramName = encodeComponent(symName ? symName : __traits(identifier, sym));
            const value = __traits(getMember, req, __traits(identifier,  sym));

            alias T = Unqual!(typeof(value));

            static if (is(T == bool))
            {
                // for bools, only add the parameter without value when true
                if (value)
                {
                    resource ~= sep ~ paramName;
                    sep = "&";
                }
            }
            else static if (is(T == string))
            {
                // for strings, only add the parameter when not null
                if (value !is null)
                {
                    resource ~= sep ~ paramName ~ "=" ~ encodeComponent(value);
                }
            }
            else
            {
                resource ~= sep ~ paramName ~ "=" ~ encodeComponent(value.to!string);
                sep = "&";
            }
        }}
        // dfmt on
    }

    return resource;
}

private Json toJson(ubyte[] raw) @trusted
{
    import std.exception : assumeUnique;

    const str = cast(string) assumeUnique(raw);
    return parseJsonString(str);
}

private string fromJson(const ref Json json)
{
    debug
    {
        return json.toPrettyString();
    }
    else
    {
        return json.toString();
    }
}

private string methodString(Method method)
{
    final switch (method)
    {
    case Method.GET:
        return "GET  ";
    case Method.POST:
        return "POST ";
    }
}

private Response!(ubyte[]) rawReq(Method method, string loginKey, string host, string resource,
    const(ubyte)[] reqBody, string contentType = null) @trusted
{
    import std.algorithm : equal, min;
    import std.conv : to;
    import std.format : format;
    import std.net.curl : CurlException, HTTP;
    import std.uni : asLowerCase;

    const url = host ~ resource;

    auto http = HTTP();
    http.url = url;

    final switch (method)
    {
    case Method.GET:
        http.method = HTTP.Method.get;
        break;
    case Method.POST:
        http.method = HTTP.Method.post;
        break;
    }

    if (loginKey)
    {
        http.addRequestHeader("Authorization", format("Bearer %s", loginKey));
    }
    if (reqBody.length)
    {
        assert(method != Method.GET);

        if (contentType)
        {
            http.addRequestHeader("Content-Type", contentType);
        }

        http.contentLength = reqBody.length;
        size_t sent = 0;
        http.onSend = (void[] buf) {
            auto b = cast(const(void)[]) reqBody;
            const len = min(b.length - sent, buf.length);
            buf[0 .. len] = b[sent .. sent + len];
            return len;
        };
    }

    ubyte[] data;
    http.onReceiveHeader = (in char[] key, in char[] value) {
        if (equal(key.asLowerCase(), "content-length"))
        {
            data.reserve(value.to!size_t);
        }
    };
    http.onReceive = (ubyte[] rcv) { data ~= rcv; return rcv.length; };

    HTTP.StatusLine status;
    http.onReceiveStatusLine = (HTTP.StatusLine sl) { status = sl; };

    try
    {
        http.perform();
    }
    catch (CurlException ex)
    {
        throw new ServerDownException(host, ex.msg);
    }

    {
        import dopamine.log : logVerbose, info, success, error;

        const codeText = format("%s", status.code);
        logVerbose("%s%s ... %s", info(methodString(method)), url,
            status.code >= 400 ? error(codeText) : success(codeText));
    }

    string error;
    if (status.code >= 400)
    {
        error = cast(string) data.idup;
    }

    return Response!(ubyte[])(data, status.code, status.reason, error);
}

version (unittest)
{
    import dopamine.api.v1;
    import unit_threaded.assertions;
}

@("requestResource")
unittest
{
    requestResource(GetPackage(17))
        .shouldEqual("/api/v1/packages/17");
    requestResource(GetPackageByName("pkgname"))
        .shouldEqual("/api/v1/packages/by-name/pkgname");
    requestResource(GetPackageRecipe(123, "1.0.0"))
        .shouldEqual("/api/v1/packages/123/recipes/1.0.0");
    requestResource(GetPackageRecipe(432, "1.0.0", "abcdef"))
        .shouldEqual("/api/v1/packages/432/recipes/1.0.0?revision=abcdef");
}
