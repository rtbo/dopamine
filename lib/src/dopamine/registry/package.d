module dopamine.registry;

import dopamine.login;
public import dopamine.registry.defs;
public import dopamine.registry.transport;

import vibe.data.json;

/// The URL of default registry the client connects to.
enum defaultRegistry = "http://localhost:3000";

/// The latest version of the remote API implemented by the client
enum latestApiLevel = 1;

class Registry
{
    private Transport transport;

    this(LoginKey key = LoginKey.init, int apiLevel = latestApiLevel)
    {
        import std.process : environment;

        const host = environment.get("DOP_REGISTRY", defaultRegistry);
        transport = Transport(host, key, apiLevel);
    }

    this(string host, LoginKey key = LoginKey.init, int apiLevel = latestApiLevel)
    {
        transport = Transport(host, key, apiLevel);
    }

    @property string host() const
    {
        return transport.host;
    }

    @property int apiLevel() const
    {
        return transport.apiLevel;
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
        Json json = Json.emptyObject;
        json["name"] = name;
        return transport.jsonPost(uri, json).mapResp!(jv => packageFromJson(jv));
    }

    Response!(string[]) getPackageVersions(string packageId, bool latestOnly)
    {
        import std.algorithm : map;
        import std.array : array;

        string[string] params;
        if (latestOnly)
        {
            params["latest"] = "true";
        }
        const uri = resource("/packages/%s/versions", packageId, params);
        return transport.jsonGet(uri).mapResp!(jv => jv[].map!(j => j.to!string).array);
    }

    /// POST a new package recipe
    Response!PackageRecipePayload postRecipe(PackageRecipePost prp)
    {
        const uri = resource("/packages/%s/recipes", prp.packageId);
        Json json = Json.emptyObject;
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
