module dopamine.client.publish;

import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.api;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.state;

import std.exception;
import std.file;
import std.format;
import std.getopt;

int publishMain(string[] args)
{
    import std.conv : to;

    string profileName;
    bool create;

    auto helpInfo = getopt(args, "profile|p", &profileName, "create|c", &create);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop build command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);

    auto profile = enforceProfileReady(dir, recipe, profileName);
    const profileDirs = dir.profileDirs(profile);

    enforce(checkBuildReady(dir, profileDirs), new FormatLogException(
            "%s: Build is not done or not up-to-date for current profile."
            ~ " You need at least one successful build for publishing.", error("Error")));

    API api;
    enforce(api.readLogin(), new FormatLogException(
            "%s: Publishing requires to be logged-in. Get a login key on the web front-end and run %s.",
            error("Error"), info("dop login [key]")));

    logInfo("%s: %s - %s", info("Login Key"), success("OK"), api.login.keyName);

    // Checking revision now as it may throw an error
    const revision = recipe.revision();

    auto packResp = api.getPackageByName(recipe.name);
    if (!packResp)
    {
        enforce(packResp.code == 404, new FormatLogException("%s: Unexpected server response: %s",
                error("Error"), packResp.code));

        if (!create)
        {
            logError("%s: package '%s' does not exist on server. Try with `--create` option.",
                    error("Error"), info(recipe.name));
            return 1;
        }

        logInfo("Will create package '%s' on server", info(recipe.name));

        packResp = api.postPackage(recipe.name);

        enforce(packResp, new FormatLogException("%s: Could not create package on server: %s - %s",
                error("Error"), error(packResp.code.to!string), packResp.error));
    }
    else if (create)
    {
        logInfo("Found package '%s' on server. Ignoring `--create` option.", info(recipe.name));
    }

    const pack = packResp.payload;

    const recipeLua = cast(string) assumeUnique(read(dir.dopamineFile()));

    const post = PackageRecipePost(pack.id, recipe.ver.toString(), revision, recipeLua);

    const resp = api.postRecipe(post);

    enforce(resp, new FormatLogException(`%s: Unexpected server response: %s - %s`,
            error("Error"), error(resp.code.to!string), resp.error));

    logInfo("%s: %s - %s/%s", info("Publish"), success("OK"),
            info(format("%s-%s", recipe.name, recipe.ver)), revision);

    return 0;
}
