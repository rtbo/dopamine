module dopamine.client.depinstall;

import dopamine.client.profile;
import dopamine.client.recipe;

import dopamine.depbuild;
import dopamine.depcache;
import dopamine.depdag;
import dopamine.log;
import dopamine.paths;
import dopamine.state;

import std.exception;
import std.getopt;
import std.path;
import std.typecons;

private string normalized(string path)
{
    return path.length ? buildNormalizedPath(absolutePath(path)) : null;
}

int depInstallMain(string[] args)
{
    string stageDest;
    string profileName;
    bool noNetwork;
    bool force;

    auto helpInfo = getopt(args, "stage", &stageDest, "profile|p",
            &profileName, "no-network|N", &noNetwork, "force|f", &force);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop depinstall command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);
    if (!recipe.hasDependencies)
    {
        logInfo("No dependencies. Nothing to do.");
        return 0;
    }

    const profile = enforceProfileReady(dir, recipe, profileName);
    const pdirs = dir.profileDirs(profile);

    const depState = checkDepInstalled(dir, pdirs);
    if (!force && depState && normalized(depState.dir) == normalized(stageDest))
    {
        if (stageDest)
            logInfo("%s: Already up-to-date at %s. Run with %s to overcome.",
                    info("Dependencies"), stageDest, info("--force"));
        else
            logInfo("%s: Already up-to-date. Run with %s to overcome.",
                    info("Dependencies"), info("--force"));
        return 0;
    }

    const network = noNetwork ? No.network : Yes.network;
    auto depcache = new DependencyCache(network);
    scope (exit)
        depcache.dispose();

    auto dag = enforce(checkLoadLockFile(dir), new FormatLogException(
            "%s: Dependencies are not locked. run %s.", error("Error"), info("dop deplock")));

    enforce(dagIsResolved(dag), new FormatLogException("%s: Dependencies not properly locked. Try to run %s",
            error("Error"), info("dop deplock --force")));

    buildDependencies(dag, recipe, profile, depcache, stageDest.absolutePath());

    dir.profileDirs(profile).depsFlag.write(stageDest);

    if (stageDest)
        logInfo("%s: %s - %s", info("Dependencies"), success("OK"), stageDest);
    else
        logInfo("%s: %s", info("Dependencies"), success("OK"));

    return 0;
}
