module dopamine.api;

import dopamine.login;
import dopamine.recipe;
import dopamine.semver;

import std.algorithm;
import std.array;
import std.format;
import std.exception;
import std.json;
import std.net.curl;

@safe:

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

/// A Package root object as retrieved with GET /packages
struct Package
{
    string id;
    string name;
    string[] versions;
}

private Package packageFromJson(const(JSONValue) json)
{
    Package p;
    p.id = json["id"].str;
    p.name = json["name"].str;
    p.versions = json["versions"].arrayNoRef.map!(v => v.str).array;
    return p;
}

/// A Package version object
/// This is the actual package definition with recipe
struct PackageVersion
{
    string packageId;
    string name;
    Semver ver;
    /// Content of dopamine.lua file. Only needed to display it in frontend.
    /// It is sent when the version is published, but not sent back in the GET
    /// requests
    string luaDef;
    const(Recipe) recipe;
}

private PackageVersion packageVersionFromJson(const(JSONValue) json)
{
    const recipe = recipeParseJson(json["recipe"]);
    return PackageVersion(json["packageId"].str, json["name"].str,
            Semver(json["version"].str), null, recipe);
}

struct API
{
    private
    {
        string _host = "http://localhost:3000";
        string _ver = "v1";
        LoginKey _login;
    }

    @property string host() const
    {
        return _host;
    }

    @property void host(string host)
    {
        _host = host;
    }

    @property string ver() const
    {
        return _ver;
    }

    @property void ver(string ver)
    {
        _ver = ver;
    }

    void readLogin()
    {
        import dopamine.login : isLoggedIn, readLoginKey;

        enforce(isLoggedIn,
                "Not logged-in. Get a CLI-key on the frontend and run `dop login [your key]`");
        _login = readLoginKey();
    }

    @property LoginKey login() const
    {
        return _login;
    }

    Response!Package getPackageByName(string name)
    {
        const uri = format("%s?name=%s", resource("/packages"), name);
        return jsonGet(uri).mapResp!(jv => packageFromJson(jv));
    }

    Response!Package postPackage(string name)
    {
        const uri = resource("/packages");
        JSONValue json;
        json["name"] = name;
        return jsonPost(uri, json).mapResp!(jv => packageFromJson(jv));
    }

    Response!PackageVersion getPackageVersion(string packageId, string ver)
    {
        const uri = resource(format("/packages/%s/versions/%s", packageId, ver));
        return jsonGet(uri).mapResp!(jv => packageVersionFromJson(jv));
    }

    Response!PackageVersion postPackageVersion(PackageVersion pver)
    {
        const uri = resource(format("/packages/%s/versions", pver.packageId));
        JSONValue jv;
        jv["name"] = pver.name;
        jv["version"] = pver.ver.toString();
        jv["luaDef"] = pver.luaDef;
        jv["recipe"] = recipeToJson(pver.recipe);
        return jsonPost(uri, jv).mapResp!(jv => packageVersionFromJson(jv));
    }

    private string resource(string path)
    {
        return format("%s/api/%s%s", _host, _ver, path);
    }

    private string resource(string path, string[string] params)
    {
        import std.array : join;

        const query = params.byKeyValue().map!(kv => format("%s=%s", kv.key, kv.value)).join("&");
        const querySt = query.length ? "?" : "";

        return format("%s/api/%s%s%s%s", _host, _ver, path, querySt, query);
    }

    private Response!JSONValue jsonGet(string url)
    {
        return rawGet(url, true).mapResp!(raw => toJson(raw));
    }

    private Response!JSONValue jsonPost(string url, const ref JSONValue bodi)
    {
        const rawbody = fromJson(bodi);
        return rawPost(url, cast(const(ubyte)[]) rawbody, true).mapResp!(raw => toJson(raw));
    }

    private Response!(ubyte[]) rawGet(string url, bool json = false)
    {
        return rawReq(url, HTTP.Method.get, [], json);
    }

    private Response!(ubyte[]) rawPost(string url, scope const(void)[] bodi, bool json = false)
    {
        return rawReq(url, HTTP.Method.post, bodi, json);
    }

    private Response!(ubyte[]) rawReq(string url, HTTP.Method method,
            scope const(void)[] bodi, bool json) @trusted
    {
        import std.algorithm : min;
        import std.conv : to;
        import std.format : format;
        import std.string : toLower;
        import std.stdio : writefln, writef;

        auto http = HTTP();
        http.url = url;
        http.method = method;
        if (_login)
        {
            http.addRequestHeader("Authorization", format("Bearer %s", _login.key));
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
