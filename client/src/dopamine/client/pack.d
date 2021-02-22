module dopamine.client.pack;

import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.client.source;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.state;
import dopamine.util;

import std.exception;
import std.file;
import std.getopt;
import std.path;

int packageMain(string[] args)
{
    string dest;
    string profileName;

    auto helpInfo = getopt(args, "dest", &dest, "profile|p", &profileName);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop package command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);

    auto profile = enforceProfileReady(dir, recipe, profileName);
    const profileDirs = dir.profileDirs(profile);

    const buildState = checkBuildReady(dir, profileDirs);
    if (!buildState)
    {
        logError("%s: Build is not up-to-date. Try `%s`.", error("Error"), info("dop build"));
        return 1;
    }

    if (!dest)
    {
        dest = profileDirs.install;
    }

    const absDest = dest.absolutePath().buildNormalizedPath();
    const absInst = profileDirs.install.absolutePath().buildNormalizedPath();

    enforce(buildState.dir.length || recipe.hasPackFunc);
    enforce(!buildState.dir.length || (exists(buildState.dir)
            && isDir(buildState.dir)));

    if (!recipe.hasPackFunc)
    {
        if (absInst != absDest)
        {
            // Copy profileDirs.install to dest
            installRecurse(absInst, absDest);
        }
    }
    else
    {
        const srcDir = enforceSourceReady(dir, recipe);
        const bd = profileDirs.buildDirs(srcDir);
        recipe.pack(bd, profile, absDest);
    }

    recipe.patchInstall(profile, absDest);

    logInfo("%s: %s - %s", info("Package"), success("OK"), dest);
    return 0;
}
