module dopamine.client.deplock;

import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.depcache;
import dopamine.depdag;
import dopamine.deplock;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.state;

import std.exception;
import std.getopt;
import std.typecons;

DepDAG enforceLoadLockFile(PackageDir dir, Recipe recipe, Profile profile, CacheRepo cache)
{
    if (!recipe.hasDependencies)
    {
        auto dag = prepareDepDAG(recipe, profile, cache, Heuristics.preferCached);
        resolveDepDAG(dag, cache);
        dagFetchLanguages(dag, recipe, cache);
        return dag;
    }

    auto dag = checkLoadLockFile(dir);
    enforce(dag && dagIsResolved(dag), new FormatLogException(
            "%s: Dependencies are not fully locked or resolved. Try to run %s",
            error("Error"), info("dop deplock")));
    return dag;
}

int depLockMain(string[] args)
{
    string profileName;
    bool force;
    Heuristics heuristics;
    bool noNetwork;

    auto helpInfo = getopt(args, "profile|p", &profileName, "heuristics|h",
            &heuristics, "force|f", &force, "no-network|N", &noNetwork);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop deplock command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);

    if (!recipe.hasDependencies)
    {
        logInfo("No dependencies. Nothing to do.");
        return 0;
    }

    const network = noNetwork ? No.network : Yes.network;
    auto depcache = new DependencyCache(network);
    scope (exit)
        depcache.dispose();

    auto dag = checkLoadLockFile(dir);

    if (!force && dag)
    {
        logInfo("Dependencies already locked. Nothing to do. You may use the %s option",
                info("force"));
        return 0;
    }

    auto profile = enforceProfileReady(dir, recipe, profileName);

    dag = prepareDepDAG(recipe, profile, depcache, heuristics);
    resolveDepDAG(dag, depcache);
    dagFetchLanguages(dag, recipe, depcache);

    dagToLockFile(dag, dir.lockFile, false);

    logInfo("%s: %s - %s", info("Dependencies"), success("OK"), dir.lockFile);

    return 0;
}
