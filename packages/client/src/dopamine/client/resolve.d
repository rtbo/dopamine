module dopamine.client.resolve;

import dopamine.client.utils;

import dopamine.cache;
import dopamine.dep.dag;
import dopamine.dep.service;
import dopamine.log;
import dopamine.recipe;
import dopamine.paths;
import dopamine.profile;
import dopamine.registry;

import std.exception;
import std.getopt;
import std.stdio;
import std.typecons;

DepDAG enforceResolved(RecipeDir rdir)
in(rdir.hasRecipeFile)
{
    import std.file : read, timeLastModified;
    import std.json : parseJSON;

    if (!rdir.hasDepsLockFile)
        throw new ErrorLogException(
            "Dependency resolution: %s - `dop.lock` doesn't exist. Try to run %s", error("NOK"), info("dop resolve"),
        );

    if (timeLastModified(rdir.depsLockFile) < timeLastModified(rdir.recipeFile))
        throw new ErrorLogException(
            "Dependency resolution: %s - `dop.lock` is out-dated. Try to run %s", error("NOK"), info("dop resolve"),
        );

    scope(success)
        logInfo("Dependency resolution: %s", success("OK"));

    const fname = rdir.depsLockFile;
    const content = cast(const(char)[])read(fname);
    auto json = parseJSON(content);
    return DepDAG.fromJson(json);
}

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
        "prefer-system", "Resolve dependencies using the `preferSystem` mode (Default)", &preferSystem,
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

    auto rdir = enforceRecipe(".");
    auto recipe = rdir.recipe;

    if (!recipe.hasDependencies)
    {
        logInfo("No dependency - nothing to do");
        return 0;
    }

    enforce(rdir.hasProfileFile, new ErrorLogException(
            "A compilation profile is needed to resolve dependencies. You may try %s.",
            info("dop profile default")
        )
    );
    auto profile = Profile.loadFromFile(rdir.profileFile);

    // FIXME: add options to modify existing lock file

    if (rdir.hasDepsLockFile && !force)
    {
        throw new ErrorLogException(
            "%s already exist, use %s to overwrite", rdir.depsLockFile, info("--force")
        );
    }

    auto cache = new PackageCache(homeCacheDir);
    auto registry = noNetwork ? null : new Registry();
    const system = noSystem ? No.system : Yes.system;

    auto service = new DependencyService(cache, registry, system);

    Heuristics heuristics;
    heuristics.mode = heuristicsMode(preferSystem, preferCache, preferLocal, pickHighest);

    // TODO: system block-list/enable-list

    try
    {
        auto dag = DepDAG.prepare(rdir, profile, service, heuristics);
        dag.resolve();

        auto json = dag.toJson();

        import std.file : write;

        write(rdir.depsLockFile, json.toPrettyString());

        logInfo("%s: %s", info("Dependency resolution"), success("OK"));
        foreach (dep; dag.traverseTopDownResolved())
        {
            logInfo("    %s/%s%s%s - from %s", dep.name, dep.ver,
                dep.revision ? "/" : "", dep.revision, dep.location);
        }
    }
    catch (ServerDownException ex)
    {
        assert(registry);
        throw new ErrorLogException(ex,
            "Server %s appears down (%s), or you might be offline. Try with %s.",
            info(ex.host), ex.reason, info("--no-network"),
        );
    }

    return 0;
}

private Heuristics.Mode heuristicsMode(bool preferSystem, bool preferCache, bool preferLocal, bool pickHighest)
{
    import std.algorithm;
    import std.range : only;

    int count = only(preferSystem, preferCache, preferLocal, pickHighest).map!(
        b => cast(int) b).sum();

    enforce(count <= 1, new ErrorLogException("Only one resolution mode must be supplied!"));

    if (preferSystem)
        return Heuristics.Mode.preferSystem;

    if (preferCache)
        return Heuristics.Mode.preferCache;

    if (preferLocal)
        return Heuristics.Mode.preferLocal;

    if (pickHighest)
        return Heuristics.Mode.pickHighest;

    return Heuristics.Mode.preferSystem;
}
