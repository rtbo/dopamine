module dopamine.api;

public import dopamine.api.defs;
import dopamine.api.transport;
import dopamine.login;

import std.json;

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
        const uri = resource("/packages");
        JSONValue json;
        json["name"] = name;
        return transport.jsonPost(uri, json).mapResp!(jv => packageFromJson(jv));
    }

    /// POST a new package version and retrieve the secured upload-url
    Response!string postVersion(PackageVersionPost pvp)
    {
        const uri = resource("/packages/%s/version", pvp.packageId);
        JSONValue json;
        json["verison"] = pvp.ver;
        json["revision"] = pvp.rev;
        return transport.jsonPost(uri, json).mapResp!(jv => jv["upload-url"].str);
    }

    private string resource(Args...)(string path, Args args)
    {
        pragma(inline, true);

        return transport.resource(path, args);
    }
}
