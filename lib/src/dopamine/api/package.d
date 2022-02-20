module dopamine.api;

public import dopamine.api.defs;
public import dopamine.api.transport;
import dopamine.login;

import std.json;

/// The URL of default registry the client connects to.
enum defaultRegistry = "http://localhost:3000";

/// The latest version of the remote API implemented by the client
enum latestApiVersion = 1;

API api(LoginKey key = LoginKey.init, int apiVersion=latestApiVersion)
{
    import std.process : environment;

    const host = environment.get("DOP_REGISTRY", defaultRegistry);
    return api(host, key, apiVersion);
}

API api(string host, LoginKey key = LoginKey.init, int apiVersion=latestApiVersion)
{
    auto transport = ApiTransport(host, key, apiVersion);
    return API(transport);
}

struct API
{
    private
    {
        ApiTransport transport;

        this(ApiTransport transport)
        {
            this.transport = transport;
        }
    }

    @disable this();

    @property string host() const
    {
        return transport.host;
    }

    @property void host(string host)
    {
        transport.host = host;
    }

    @property int ver() const
    {
        return transport.apiVersion;
    }

    @property void ver(int ver)
    {
        transport.apiVersion = ver;
    }

    bool readLogin()
    {
        if (!isLoggedIn)
            return false;
        transport.login = readLoginKey();
        return true;
    }

    @property LoginKey login() const
    {
        return transport.login;
    }

    Response!PackagePayload getPackageByName(string name)
    {
        const uri = resource("/packages", ["name": name]);
        return transport.jsonGet(uri).mapResp!(jv => packageFromJson(jv));
    }

    Response!PackagePayload postPackage(string name)
    {
        const uri = resource("/packages");
        JSONValue json;
        json["name"] = name;
        return transport.jsonPost(uri, json).mapResp!(jv => packageFromJson(jv));
    }

    Response!(string[]) getPackageVersions(string packageId, bool latestOnly)
    {
        string[string] params;
        if (latestOnly)
        {
            params["latest"] = "true";
        }
        const uri = resource("/packages/%s/versions", packageId, params);
        return transport.jsonGet(uri).mapResp!(jv => jv.jsonStringArray);
    }

    /// POST a new package recipe
    Response!PackageRecipePayload postRecipe(PackageRecipePost prp)
    {
        const uri = resource("/packages/%s/recipes", prp.packageId);
        JSONValue json;
        json["version"] = prp.ver;
        json["revision"] = prp.rev;
        json["recipe"] = prp.recipe;
        return transport.jsonPost(uri, json).mapResp!(jv => packageRecipeFromJson(jv));
    }

    Response!PackageRecipePayload getRecipe(PackageRecipeGet prg)
    {
        string[string] params;
        if (prg.rev)
        {
            params["revision"] = prg.rev;
        }
        const uri = resource("/packages/%s/recipes/%s", prg.packageId, prg.ver, params);
        return transport.jsonGet(uri).mapResp!(jv => packageRecipeFromJson(jv));
    }

    private string resource(Args...)(string path, Args args)
    {
        pragma(inline, true);

        return transport.resource(path, args);
    }
}
