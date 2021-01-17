module dopamine.api;

public import dopamine.api.defs;
import dopamine.api.transport;
import dopamine.login;

struct API
{
    private
    {
        ApiTransport transport;
    }

    @property string host() const
    {
        return transport.host;
    }

    @property void host(string host)
    {
        transport.host = host;
    }

    @property string ver() const
    {
        return transport.ver;
    }

    @property void ver(string ver)
    {
        transport.ver = ver;
    }

    void readLogin()
    {
        import std.exception : enforce;

        enforce(isLoggedIn,
                "Not logged-in. Get a CLI-key on the frontend and run `dop login [your key]`");
        transport.login = readLoginKey();
    }

    @property LoginKey login() const
    {
        return transport.login;
    }

    Response!Package getPackageByName(string name)
    {
        import std.format : format;

        const uri = format("%s?name=%s", resource("/packages"), name);
        return transport.jsonGet(uri).mapResp!(jv => packageFromJson(jv));
    }

    Response!Package postPackage(string name)
    {
        import std.json : JSONValue;

        const uri = resource("/packages");
        JSONValue json;
        json["name"] = name;
        return transport.jsonPost(uri, json).mapResp!(jv => packageFromJson(jv));
    }

    private string resource(string path)
    {
        import std.format : format;

        return format("%s/api/%s%s", transport.host, transport.ver, path);
    }

    private string resource(string path, string[string] params)
    {
        import std.algorithm : map;
        import std.array : join;
        import std.format : format;

        const query = params.byKeyValue().map!(kv => format("%s=%s", kv.key, kv.value)).join("&");
        const querySt = query.length ? "?" : "";

        return format("%s/api/%s%s%s%s", transport.host, transport.ver, path, querySt, query);
    }
}
