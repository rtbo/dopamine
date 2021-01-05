module dopamine.client.deps_install;

import dopamine.client.build;
import dopamine.client.deps_lock;
import dopamine.client.profile;
import dopamine.client.source;
import dopamine.client.util;

import dopamine.depcache;
import dopamine.depdag;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.state;

import std.file;
import std.format;
import std.getopt;

int depsInstallMain(string[] args)
{
    string profileName;

    auto helpInfo = getopt(args, "profile", "override profile for this invocation", &profileName);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop build command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    const recipe = parseRecipe(dir);

    if (!recipe.dependencies.length)
    {
        logInfo("%s has no dependency. Nothing to do.", info(recipe.name));
        return 0;
    }

    auto deps = enforceDepsLocked(dir, recipe);
    auto profile = enforceProfileReady(dir, recipe, deps, profileName);

    DepPack[] traversed;

    void installDep(DepPack pack, DepNode[] previous)
    {
        import std.algorithm : canFind;

        if (pack is deps)
            return;
        if (traversed.canFind(pack))
            return;
        traversed ~= pack;

        auto node = pack.resolvedNode;
        if (!node)
            return;

        const path = userPackageDir(node.pack.name, node.ver);
        if (!exists(path))
        {
            DependencyCache.get.cachePackage(node.pack.name, node.ver);
        }

        const ddir = PackageDir.enforced(path);
        const drec = recipeParseFile(ddir.dopamineFile());
        auto src = checkSourceReady(ddir, drec);
        if (!src)
        {
            src = drec.source.fetch(ddir);
        }

        const did = format("%s-%s", node.pack.name, node.ver);

        auto dprof = profile.subset(node.langs);
        logInfo("building %s with profile %s", info(did), info(dprof.name));
        const pdirs = ddir.profileDirs(dprof);
        if (!checkConfigReady(ddir, pdirs))
        {
            drec.build.configure(src, pdirs, dprof);
        }
        if (!checkBuildReady(ddir, pdirs))
        {
            drec.build.build(pdirs);
        }
        if (!checkInstallReady(ddir, pdirs))
        {
            drec.build.install(pdirs);
        }
        else
        {
            logInfo("   nothing to do");
        }
        logInfo("%s installed in %s", info(did), info(pdirs.install));

        previous ~= node;

        foreach(e; pack.upEdges)
        {
            installDep(e.up.pack, previous);
        }
    }

    auto leaves = collectDAGLeaves(deps);
    foreach (l; leaves)
    {
        installDep(l, []);
    }

    return 0;
}
