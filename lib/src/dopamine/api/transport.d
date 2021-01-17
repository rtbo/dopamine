module dopamine.api.transport;

import std.json;
import std.net.curl;

/// An error that correspond to a server response code >= 400
class ErrorResponseException : Exception
{
    /// The HTTP code of the response
    int code;
    /// A phrase that maps with the status code (e.g. "OK" or "Not Found")
    string reason;
    /// A message that might be given by the server in case of error.
    string error;

    this(int code, string reason, string error)
    {
        import std.format : format;

        this.code = code;
        this.reason = reason;
        this.error = error;
        super(format("Error: Server response is %s - %s: %s", code, reason, error));
    }
}

/// An error that correspond to a server seemingly down
class ServerDownException : Exception
{
    /// The URL of the server
    string host;
    /// A message from Curl backend
    string reason;

    this(string host, string reason)
    {
        import std.format : format;

        this.host = host;
        this.reason = reason;
        super(format("Error: Server %s appears to be down: %s", host, reason));
    }
}

/// Response returned by the API
struct Response(T)
{
    /// The data returned in the response
    private T _payload;
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

template mapResp(alias pred)
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

struct ApiTransport
{
    import dopamine.login : LoginKey;

    string host = "http://localhost:3000";
    string ver = "v1";
    LoginKey login;

    Response!JSONValue jsonGet(string url)
    {
        return rawGet(url, true).mapResp!(raw => toJson(raw));
    }

    Response!JSONValue jsonPost(string url, const ref JSONValue bodi)
    {
        const rawbody = fromJson(bodi);
        return rawPost(url, cast(const(ubyte)[]) rawbody, true).mapResp!(raw => toJson(raw));
    }

    Response!(ubyte[]) rawGet(string url, bool json = false)
    {
        return rawReq(url, HTTP.Method.get, [], json);
    }

    Response!(ubyte[]) rawPost(string url, scope const(void)[] bodi, bool json = false)
    {
        return rawReq(url, HTTP.Method.post, bodi, json);
    }

    Response!(ubyte[]) rawReq(string url, HTTP.Method method, scope const(void)[] bodi, bool json) @trusted
    {
        import std.algorithm : min;
        import std.conv : to;
        import std.format : format;
        import std.string : toLower;
        import std.stdio : writefln, writef;

        auto http = HTTP();
        http.url = url;
        http.method = method;
        if (login)
        {
            http.addRequestHeader("Authorization", format("Bearer %s", login.key));
        }
        if (bodi.length)
        {
            assert(method != HTTP.Method.get);

            if (json)
            {
                http.addRequestHeader("Content-Type", "application/json");
            }

            http.contentLength = bodi.length;
            size_t sent = 0;
            http.onSend = (void[] buf) {
                auto b = cast(const(void)[]) bodi;
                const len = min(b.length - sent, buf.length);
                buf[0 .. len] = b[sent .. sent + len];
                return len;
            };
        }

        ubyte[] data;
        http.onReceiveHeader = (in char[] key, in char[] value) {
            if (key.toLower() == "content-length")
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
            import dopamine.log : logInfo, info, success, error;

            const codeText = format("%s", status.code);
            logInfo("%s%s ... %s", info(methodString(method)), url,
                    status.code >= 400 ? error(codeText) : success(codeText));
        }

        string error;
        if (status.code >= 400)
        {
            error = cast(string) data.idup;
        }

        return Response!(ubyte[])(data, status.code, status.reason, error);
    }
}

private JSONValue toJson(ubyte[] raw) @trusted
{
    import std.exception : assumeUnique;

    const str = cast(string) assumeUnique(raw);
    return parseJSON(str);
}

private string fromJson(const ref JSONValue json)
{
    debug
    {
        enum pretty = true;
    }
    else
    {
        enum pretty = false;
    }
    return toJSON(json, pretty);
}

private string methodString(HTTP.Method method)
{
    switch (method)
    {
    case HTTP.Method.get:
        return "GET    ";
    case HTTP.Method.post:
        return "POST   ";
    case HTTP.Method.put:
        return "PUT    ";
    case HTTP.Method.del:
        return "DELETE ";
    default:
        assert(false);
    }
}
