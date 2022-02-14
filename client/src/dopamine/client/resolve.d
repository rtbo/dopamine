module dopamine.client.resolve;

import dopamine.client.utils;

import dopamine.dep.dag;
import dopamine.log;
import dopamine.paths;

import std.getopt;
import std.stdio;
import std.typecons;

int resolveMain(string[] args)
{
    bool force;
    bool preferSystem;
    bool preferCache;
    bool preferLocal;
    bool pickHighest;
    bool noNetwork;
    bool noSystem;

    auto helpInfo = getopt(args,
        "force|f", "Resolve dependencies and overwrite lock file", &force,
        "prefer-system", "Resolve dependencies using the `preferSystem` mode", &preferSystem,
        "prefer-cache", "Resolve dependencies using the `preferCache` mode", &preferCache,
        "prefer-local", "Resolve dependencies using the `preferLocal` mode", &preferLocal,
        "pick-highest", "Resolve dependencies using the `pickHighest` mode", &pickHighest,
        "no-network|N", "Resolve dependencies without using network", &noNetwork,
        "no-system", "Resolve dependencies without using system installed packages", &noSystem,
    );

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("Dopamine deplock command", helpInfo.options);
        return 0;
    }

    auto dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);

    if (!recipe.hasDependencies)
    {
        logInfo("No dependency - nothing to do");
        return 0;
    }

    if (dir.hasLockFile && !force)
    {
        logError(
            "%s %s already exist, use %s to overwrite",
            error("Error:"), dir.lockFile, info("--force")
        );
        return 1;
    }

    const network = noNetwork ? No.network : Yes.network;
    const system = noSystem ? No.system : Yes.system;



    return 0;
}
