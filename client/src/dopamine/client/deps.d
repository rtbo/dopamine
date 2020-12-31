module dopamine.client.deps;

import dopamine.depcache;
import dopamine.depdag;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.state;

int depsMain(string[] args)
{
    const packageDir = PackageDir.enforced(".");
    const recipe = recipeParseFile(packageDir.dopamineFile);

    if (!recipe.dependencies)
    {
        logInfo("%s has not dependencies: nothing to do!", info(recipe.name));
        return 0;
    }

    auto state = new class(packageDir, recipe) LockFileState
    {
        this(PackageDir packageDir, const(Recipe) recipe)
        {
            super(packageDir, recipe);
        }

        protected override void doReach()
        {
            auto dag = prepareDepDAG(recipe, DependencyCache.get);
            checkDepDAGCompat(dag);
            resolveDepDAG(dag, DependencyCache.get, Heuristics.preferCached);

            traverseResolvedNodesTopDown(dag, (DepNode node) @safe {
                if (node.pack is dag)
                    return;

                DependencyCache.get.cachePackage(node.pack.name, node.ver);
            });

            dagToLockFile(dag, packageDir.lockFile, false);

            dagRoot = dag;
        }
    };

    if (state.reached)
    {
        logInfo("lock-file is up-to-date - nothing to do");
    }
    else
    {
        state.reach();
        logInfo("Lock-file written to %s", info(packageDir.lockFile));
    }

    return 0;
}
