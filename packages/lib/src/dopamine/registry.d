module dopamine.registry;

import dopamine.api.attrs;
import dopamine.log;
import dopamine.login;

import std.algorithm;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.process;
import std.string;
import core.time;

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

    this(Method method, string url, string file = __FILE__, size_t line = __LINE__)
    {
        import std.format : format;

        this.url = url;
        super(format(
                "%s \"%s\" requires authentication. You need to get a token from " ~
                environment.get(
                "DOP_REGISTRY", defaultRegistry) ~ ".",
                method, url
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

/// Thrown if the request could not be parsed into a resource
class WrongRequestException : Exception
{
    mixin basicExceptionCtors!();
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

/// Metadata returned when downloading a file
struct DownloadMetadata
{
    string filename;
    ubyte[] sha256;
}

/// The URL of default registry the client connects to.
enum defaultRegistry = "https://localhost:3500";

/// Client interface to the registry.
class Registry
{
    string _host;
    string _idToken;
    SysTime _idTokenExp;

    this()
    {
        _host = checkHost(environment.get("DOP_REGISTRY", defaultRegistry));
    }

    this(string host)
    {
        _host = checkHost(host);
    }

    @property string host() const
    {
        return _host;
    }

    @property bool isLoggedIn()
    {
        return _idToken && _idTokenExp > Clock.currTime;
    }

    void ensureAuth()
    {
        import dopamine.api.auth;
        import jwt;

        if (_idToken && _idTokenExp > Clock.currTime)
            return;
        string registry = _host.find("://")[3 .. $];

        (() @trusted {
            enforce(hasLoginToken(registry), new ErrorLogException(
                "No token found for registry %s", info(registry)
            ));
        })();

        auto req = PostAuthToken(readLoginToken(registry));
        AuthToken resp = sendRequest(req).payload;
        writeLoginToken(registry, resp.refreshToken);
        _idToken = resp.idToken;
        const payload = ClientJwt(_idToken).payload;
        _idTokenExp = fromJwtTime(payload["exp"].get!long);

        logInfo("Authenticated on %s - %s", info(registry), info(payload["email"]));
    }

    Response!(ResponseType!ReqT) sendRequest(ReqT)(auto ref const ReqT req) @safe
            if (isRequest!ReqT)
    {
        import std.conv : to;
        import std.traits : hasUDA;

        enum reqAttr = RequestAttr!ReqT;
        enum method = reqAttr.method;
        enum requiresAuth = hasUDA!(ReqT, RequiresAuth);

        RawRequest raw;
        raw.method = method.toCurl();
        raw.resource = requestResource(req);
        raw.host = host;
        static if (method == Method.POST)
        {
            auto json = serializeToJsonString(req);
            raw.body_ = json.representation;
            raw.contentType = "application/json";
        }
        static if (requiresAuth)
        {
            enforce(isLoggedIn, new AuthRequiredException(method, reqAttr.resource));
            raw.headers["Authorization"] = format!"Bearer %s"(_idToken);
        }

        auto res = perform(raw).asResponse();

        static if (hasResponse!ReqT)
        {
            alias ResT = ResponseType!ReqT;
            // res.payload is unique because allocated in perform and not shared
            return res.mapResp!((data) @trusted => toJson(assumeUnique(data))
                    .deserializeJson!(ResT)());
        }
        else
        {
            return res.toVoid;
        }
    }

    /// Return an input range of const(ubyte)[].
    /// First a HEAD request is sent to check the data length and to
    /// check if the server supports Range requests.
    /// Then the returned range perform a data request each time the popFront is called.
    /// Throws ErrorResponseException if a status code >= 400 is returned.
    auto download(ReqT)(auto ref const ReqT req, out DownloadMetadata metadata)
            if (isDownloadEndpoint!ReqT)
    {
        import std.traits : hasUDA;

        enum reqAttr = RequestAttr!ReqT;
        static assert(
            reqAttr.method == Method.GET,
            "Download end-points are only valid for GET requests"
        );

        enum requiresAuth = hasUDA!(ReqT, RequiresAuth);
        static if (requiresAuth)
        {
            enforce(isLoggedIn, new AuthRequiredException(reqAttr.url));
        }

        // HEAD request
        RawRequest raw;
        raw.method = HTTP.Method.head;
        raw.host = host;
        raw.resource = requestResource(req);
        static if (requiresAuth)
            raw.headers["Authorization"] = format!"Bearer %s"(_idToken);
        raw.headers["Want-Digest"] = "sha-256";

        RawResponse resp = perform(raw);
        if (resp.status.code >= 400)
            throw new ErrorResponseException(
                resp.status.code, resp.status.reason, cast(string)(resp.body_.idup)
            );

        size_t contentLength;
        if (auto p = "content-length" in resp.headers)
            contentLength = (*p).to!size_t;

        bool acceptRanges;
        if (auto p = "accept-ranges" in resp.headers)
            acceptRanges = *p == "bytes" && contentLength > 0;

        if (auto p = "content-disposition" in resp.headers)
        {
            auto head = *p;
            if (head.startsWith("attachment;"))
            {
                head = head["attachment;".length .. $].strip();
                if (head.startsWith("filename="))
                    metadata.filename = head["filename=".length .. $];
            }
        }

        if (auto p = "digest" in resp.headers)
        {
            auto head = *p;
            if (head.startsWith("sha-256="))
            {
                import std.base64;

                metadata.sha256 = Base64.decode(head["sha-256=".length .. $].strip());
            }
        }

        // enum size_t chunkSize = 1024 * 1024;
        enum size_t chunkSize = 256;

        const chunkData = acceptRanges && contentLength > chunkSize;

        // GET request
        raw.method = HTTP.Method.get;
        if (contentLength > 0)
            raw.respBuf = new ubyte[min(contentLength, chunkSize)];

        raw.headers.remove("Want-Digest");
        if (chunkData)
            raw.headers["Range"] = format!"bytes=0-%s"(chunkSize - 1);

        resp = perform(raw);

        if (resp.status.code >= 400)
            throw new ErrorResponseException(
                resp.status.code, resp.status.reason, cast(string)(resp.body_.idup)
            );

        if (chunkData)
        {
            enforce(
                resp.headers["content-range"] == format!"bytes 0-%s/%s"(chunkSize - 1, contentLength)
            );
        }

        static struct DownloadRange
        {
            size_t received;
            size_t contentLength;
            const(ubyte)[] data;
            RawRequest rawReq;

            @property const(ubyte)[] front()
            {
                return data;
            }

            @property bool empty()
            {
                return data.length == 0;
            }

            void popFront()
            {
                received += data.length;
                data = null;

                if (received == contentLength)
                    return;

                const sz = min(chunkSize, contentLength - received);
                const end = received + sz - 1;
                rawReq.headers["Range"] = format!"bytes=%s-%s"(received, end);
                auto resp = perform(rawReq);
                if (resp.status.code >= 400)
                    throw new ErrorResponseException(
                        resp.status.code, resp.status.reason, cast(string)(resp.body_.idup)
                    );
                enforce(
                    resp.headers["content-range"] == format!"bytes %s-%s/%s"(received, end, contentLength)
                );
                data = resp.body_;
            }
        }

        return DownloadRange(0, contentLength, resp.body_, raw);
    }
}

private:

import vibe.data.json;
import std.net.curl : CurlException, HTTP;

string checkHost(string host)
{
    import std.exception : enforce;
    import std.string : endsWith, startsWith;

    enforce(
        !host.endsWith("/"),
        new InvalidRegistryHostException(host, "The final '/' must be removed")
    );
    return host;
}

/// resource path for GET requests
/// translates parameters (e.g. id in /recipes/:id) with the value of the
/// corresponding member in the request object
string requestResource(ReqT)(auto ref const ReqT req)
        if (isRequestFor!(ReqT, Method.GET))
{
    import std.array : split;
    import std.conv : to;
    import std.traits : getUDAs, getSymbolsByUDA, Unqual;
    import std.uri : encodeComponent;

    enum reqAttr = RequestAttr!ReqT;
    static assert(
        reqAttr.resource.length > 1 && reqAttr.resource[0] == '/',
        "Invalid resource URL: " ~ reqAttr.resource ~ " (must start by '/')"
    );

    enum prefix = "/api";
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

            const comp = encodeComponent(value.to!string);
            if (!comp)
                throw new WrongRequestException(
                    "could not associate a value to '" ~ part ~ "' for request " ~ ReqT.stringof
                );

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

/// resource path for POST requests
/// Return the resource member of the Request attribute directly. (known at compile time)
/// Does a few compile time checks as well before
/// The request member are not used here, for POST request they are translated to JSON
string requestResource(ReqT)(auto ref const ReqT req)
        if (isRequestFor!(ReqT, Method.POST))
{
    import std.traits : getUDAs, getSymbolsByUDA;

    pragma(inline, true);

    enum reqAttr = RequestAttr!ReqT;
    static assert(
        reqAttr.resource.length > 1 && reqAttr.resource[0] == '/',
        "Invalid resource URL: " ~ reqAttr.resource ~ " (must start by '/')"
    );

    static assert(!reqAttr.resource.canFind(":"), "URL parameters not allowed for POST requests");
    static assert(getSymbolsByUDA!(ReqT, Query).length == 0, "Query parameters not allowed for POST");

    enum result = format!"/api%s"(reqAttr.resource);
    return result;
}

Json toJson(immutable(ubyte)[] raw) @safe
{
    const str = cast(immutable(char)[]) raw;
    return parseJsonString(str);
}

string fromJson(const ref Json json)
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

string methodString(HTTP.Method method)
{
    switch (method)
    {
    case HTTP.Method.get:
        return "GET  ";
    case HTTP.Method.post:
        return "POST ";
    case HTTP.Method.head:
        return "HEAD ";
    default:
        assert(false);
    }
}

HTTP.Method toCurl(Method method)
{
    final switch (method)
    {
    case Method.GET:
        return HTTP.Method.get;
    case Method.POST:
        return HTTP.Method.post;
    }
}

struct RawRequest
{
    HTTP.Method method;
    string host;
    string resource;
    string[string] headers;
    string contentType;
    const(ubyte)[] body_;
    ubyte[] respBuf;

    @property string url() const @safe
    {
        return host ~ resource;
    }
}

struct RawResponse
{
    HTTP.StatusLine status;
    // headers are provided with lowercase keys
    string[string] headers;
    const(ubyte)[] body_;

    Response!(const(ubyte)[]) asResponse() const
    {
        Response!(const(ubyte)[]) resp;
        resp.code = status.code;
        resp.reason = status.reason;

        if (resp.code >= 400)
            resp.error = cast(string) body_.idup;
        else
            resp._payload = body_;

        return resp;
    }
}

RawResponse perform(RawRequest req) @trusted
{
    import dopamine.log;

    import std.uni : asLowerCase;
    import std.utf : toUTF8;

    auto http = HTTP();
    http.url = req.url;
    http.method = req.method;

    foreach (k, v; req.headers)
        http.addRequestHeader(k, v);

    if (req.body_.length)
    {
        assert(req.method != HTTP.Method.get);

        http.contentLength = req.body_.length;
        if (req.contentType)
            http.setPostData(cast(const(void)[]) req.body_, req.contentType);
        else
            http.postData = cast(const(void)[]) req.body_;
    }

    auto buf = req.respBuf;
    RawResponse resp;

    http.onReceiveStatusLine = (HTTP.StatusLine sl) { resp.status = sl; };

    http.onReceiveHeader = (in char[] key, in char[] value) {
        const ikey = assumeUnique(key.asLowerCase().toUTF8());
        const ival = value.idup;
        resp.headers[ikey] = ival;
        if (ikey == "content-length" && req.method != HTTP.Method.head)
        {
            const len = ival.to!size_t;
            if (buf.length < len)
                buf = new ubyte[len];
        }
    };

    http.onReceive = (ubyte[] rcv) {
        const len = resp.body_.length + rcv.length;
        if (buf.length < len)
            buf.length = len;
        buf[resp.body_.length .. len] = rcv;
        resp.body_ = buf[0 .. len];
        return rcv.length;
    };

    http.operationTimeout = dur!"seconds"(30);

    try
    {
        http.perform();
    }
    catch (CurlException ex)
    {
        throw new ServerDownException(req.host, ex.msg);
    }

    if (LogLevel.verbose >= minLogLevel)
    {
        const codeText = resp.status.code.to!string;
        logVerbose("%s%s ... %s", info(methodString(req.method)), req.url,
            resp.status.code >= 400 ? error(codeText) : success(codeText));
    }

    return resp;
}

version (unittest)
{
    import dopamine.api.v1;
    import unit_threaded.assertions;
}

@("requestResource")
unittest
{
    requestResource(GetPackage("pkga"))
        .shouldEqual("/api/v1/packages/pkga");

    requestResource(GetLatestRecipeRevision("pkga", "1.0.0"))
        .shouldEqual("/api/v1/packages/pkga/1.0.0/latest");

    requestResource(GetRecipeRevision("pkga", "1.0.0", "somerev"))
        .shouldEqual("/api/v1/packages/pkga/1.0.0/somerev");

    requestResource(GetRecipeRevision("pkga", "1.0.0", null))
        .shouldThrow();
}
