module dopamine.client.stage;

import dopamine.client.build;
import dopamine.client.profile;
import dopamine.client.resolve;
import dopamine.client.source;
import dopamine.client.utils;

import dopamine.build_id;
import dopamine.cache;
import dopamine.dep.build;
import dopamine.dep.resolve;
import dopamine.dep.service;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.registry;
import dopamine.util;

import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.typecons;

void stagePackage(
    RecipeDir rdir,
    Profile profile,
    string absDest,
    OptionSet options,
    DepGraphBuildInfo dgbi,
    const(DgNode) dnode)
in (isAbsolute(absDest))
{
    const config = BuildConfig(profile.subset(rdir.recipe.tools), options.forRoot());
    const buildId = BuildId(rdir.recipe, config, dgbi.nodeDirectDepBuildInfos(dnode), absDest);
    const bPaths = rdir.buildPaths(buildId);
    acquireBuildLockFile(bPaths);

    if (!rdir.recipe.canStage)
    {
        string reason;
        if (!rdir.checkBuildReady(buildId, reason))
        {
            buildPackage(rdir, config, dgbi, dnode, absDest);
        }
        return;
    }

    enforceBuildReady(rdir, buildId);
    rdir.recipe.stage(bPaths.install, absDest);
}

int stageMain(string[] args)
{
    string profileName;
    string[] optionOverrides;

    // dfmt off
    auto helpInfo = getopt(args,
        "profile|p", "Stage for the given profile.", &profileName,
        "option|o", "Override option", &optionOverrides,
    );
    // dfmt on

    if (helpInfo.helpWanted)
    {
        // FIXME: document positional argument
        defaultGetoptPrinter("dop stage command", helpInfo.options);
        return 0;
    }

    enforce(args.length == 2, "Destination expected as positional argument");
    const dest = args[1];
    const absDest = absolutePath(dest);

    auto rdir = enforceRecipe();
    auto lock = acquireRecipeLockFile(rdir);

    auto recipe = rdir.recipe;

    const srcDir = enforceSourceReady(rdir).absolutePath();

    auto profile = enforceProfileReady(rdir, profileName);

    if (rdir.recipe.isDop)
        logInfo("%s: %s", info("Revision"), info(rdir.calcRecipeRevision()));

    auto options = rdir.readOptionFile();
    foreach (oo; optionOverrides)
    {
        parseOptionSpec(options, oo);
    }

    DepGraphBuildInfo dgbi;
    Rebindable!(const(DgNode)) rootNode;
    if (recipe.hasDependencies)
    {
        auto dag = enforceResolved(rdir);
        auto services = DepServices(
            buildDepService(Yes.system, homeCacheDir(), null),
            buildDubDepService(homeDubCacheDir(), null),
        );

        dgbi = calcDepBuildInfos(dag, rdir.recipe, profile, services, options.forDependencies(), absDest);

        foreach (dn; dag.traverseTopDown())
        {
            auto service = services[dn.kind];
            auto drdir = service.packRecipe(dn.name, dn.aver, dn.revision);
            auto dprof = profile.subset(drdir.recipe.tools);

            stagePackage(drdir, dprof, absDest, options.forDependency(dn.name), dgbi.nodeDeepDepBuildInfos(dn), dn);
        }

        rootNode = dag.root;
    }

    stagePackage(rdir, profile.subset(recipe.tools), absDest, options.forRoot(), dgbi, rootNode);

    logInfo("Stage: %s - %s", success("OK"), info(dest));

    return 0;
}
