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
        const uri = resource("/packages", ["name":name]);
        return transport.jsonGet(uri).mapResp!(jv => packageFromJson(jv));
    }

    Response!Package postPackage(string name)
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
    Response!PackageRecipe postRecipe(PackageRecipePost prp)
    {
        const uri = resource("/packages/%s/recipes", prp.packageId);
        JSONValue json;
        json["version"] = prp.ver;
        json["revision"] = prp.rev;
        return transport.jsonPost(uri, json).mapResp!(jv => packageRecipeFromJson(jv));
    }

    Response!PackageRecipe getRecipe(PackageRecipeGet prg)
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
