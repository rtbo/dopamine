module dopamine.client.deps;

import dopamine.client.util;

import dopamine.depcache;
import dopamine.depdag;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.state;

DepPack enforceDepsLocked(PackageDir dir, const(Recipe) recipe)
{
    import std.exception : enforce;

    if (recipe.dependencies.length)
    {
        auto deps = checkLoadLockFile(dir);

        enforce(deps, new FormatLogException("%s: %s dependencies are not properly locked. Try to run `%s`.",
                error("Error"), info(recipe.name), info("dop deps")));

        logInfo("%s: %s - %s", info("Dependency-lock"), success("OK"), dir.lockFile);

        return deps;
    }
    else
    {
        // Recipe without dependencies yield a single root node
        auto deps = prepareDepDAG(recipe, DependencyCache.get);
        resolveDepDAG(deps, DependencyCache.get, Heuristics.preferCached);
        dagFetchLanguages(deps, recipe, DependencyCache.get);

        logInfo("%s: %s - not needed", info("Dependencies-lock"), success("OK"));

        return deps;
    }
}

DepPack lockDeps(PackageDir dir, const(Recipe) recipe)
{
    auto dag = prepareDepDAG(recipe, DependencyCache.get);
    checkDepDAGCompat(dag);
    resolveDepDAG(dag, DependencyCache.get, Heuristics.preferCached);
    dagFetchLanguages(dag, recipe, DependencyCache.get);

    traverseResolvedNodesTopDown(dag, (DepNode node) @safe {
        if (node.pack is dag)
            return;
        DependencyCache.get.cachePackage(node.pack.name, node.ver);
    });

    dagToLockFile(dag, dir.lockFile, false);
    return dag;
}

int depsMain(string[])
{
    const dir = PackageDir.enforced(".");
    const recipe = parseRecipe(dir);

    if (!recipe.dependencies)
    {
        logInfo("%s has no dependency: nothing to do", info(recipe.name));
    }
    else if (checkLockFile(dir))
    {
        logInfo("lock-file is up-to-date - nothing to do");
    }
    else
    {
        lockDeps(dir, recipe);
        logInfo("Lock-file written to %s", info(dir.lockFile));
    }

    return 0;
}
