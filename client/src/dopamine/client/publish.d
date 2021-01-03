module dopamine.client.publish;

import dopamine.client.build;
import dopamine.client.deps;
import dopamine.client.profile;
import dopamine.client.source;
import dopamine.client.util;

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

    auto helpInfo = getopt(args, "profile", "override profile for this invocation",
            &profileName, "create|c", "create package on server if it doesn't exist", &create,);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop build command", helpInfo.options);
        return 0;
    }

    const packageDir = PackageDir.enforced(".");

    const recipe = parseRecipe(packageDir);

    auto deps = enforceDepsLocked(packageDir, recipe);

    auto profile = enforceProfileReady(packageDir, recipe, deps, profileName);

    enforceBuildReady(packageDir, recipe, profile);

    const archiveFile = checkArchiveReady(packageDir, recipe, profile);

    enforce(archiveFile, new FormatLogException("The archive file %s does not exist or is not up-to-date.\n"
            ~ "Dop must check that the package actually builds with one profile before publishing.\n"
            ~ "Maybe run `dop package` before?", info(archiveFile)));

    logInfo("%s: %s - %s", info("Archive"), success("OK"), archiveFile);

    API api;
    api.readLogin();

    logInfo("%s: %s - %s", info("Login Key"), success("OK"), api.login.keyName);

    auto packResp = api.getPackageByName(recipe.name);
    if (!packResp)
    {
        enforce(packResp.code == 404, format("Unexpected server response: %s", packResp.code));

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

    const luaDef = cast(string) assumeUnique(read(packageDir.dopamineFile()));

    const pver = PackageVersion(pack.id, pack.name, recipe.ver, luaDef, recipe);

    const resp = api.postPackageVersion(pver);

    enforce(resp, new FormatLogException(`%s: Unexpected server response: %s - %s`,
            error("Error"), error(resp.code.to!string), resp.error));

    return 0;
}
