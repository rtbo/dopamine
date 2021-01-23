module dopamine.client.deplock;

import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.depcache;
import dopamine.depdag;
import dopamine.deplock;
import dopamine.log;
import dopamine.paths;
import dopamine.state;

import std.getopt;

int depLockMain(string[] args)
{
    string profileName;
    bool force;
    Heuristics heuristics;

    auto helpInfo = getopt(args, "profile|p", &profileName, "heuristics|h",
            &heuristics, "force|f", &force);

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

    auto depcache = new DependencyCache;
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
