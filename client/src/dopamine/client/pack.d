module dopamine.client.pack;

import dopamine.client.deplock;
import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.client.source;
import dopamine.depbuild;
import dopamine.depcache;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.state;
import dopamine.util;

import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.typecons;

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

    auto cache = new DependencyCache(No.network);
    scope (exit)
        cache.dispose();

    auto dag = enforceLoadLockFile(dir, recipe, profile, cache);

    const depState = checkDepInstalled(dir, profileDirs);
    if (!depState && recipe.hasDependencies)
    {
        logError("%s: Dependencies are not installed. Try `%s`.",
                error("Error"), info("dop depinstall"));
        return 1;
    }

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

    auto depInfos = dagCollectDepInfos(dag, recipe, profile, cache, depState.dir);

    const absDest = dest.absolutePath().buildNormalizedPath();
    const absInst = profileDirs.install.absolutePath().buildNormalizedPath();

    enforce(buildState.dir.length || recipe.hasPackFunc);
    enforce(!buildState.dir.length || (exists(buildState.dir) && isDir(buildState.dir)));

    const srcDir = enforceSourceReady(dir, recipe);
    const bd = profileDirs.buildDirs(srcDir);

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
        recipe.pack(bd.toPack(absDest), profile, depInfos);
    }

    recipe.patchInstall(bd.toPack(absDest), profile, depInfos);

    logInfo("%s: %s - %s", info("Package"), success("OK"), dest);
    return 0;
}
