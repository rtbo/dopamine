module dopamine.client.stage;

import dopamine.client.build;
import dopamine.client.profile;
import dopamine.client.resolve;
import dopamine.client.source;
import dopamine.client.utils;

import dopamine.build_id;
import dopamine.cache;
import dopamine.dep.build;
import dopamine.dep.service;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.registry;
import dopamine.state;
import dopamine.util;

import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.typecons;

void stagePackage(RecipeDir rdir, Profile profile, string absDest, DepInfo[string] depInfos)
in(isAbsolute(absDest))
{
    if (!rdir.recipe.canStage)
    {
        const config = BuildConfig(profile);
        const buildId = BuildId(rdir.recipe, config, absDest);
        const bPaths = rdir.buildPaths(buildId);
        acquireBuildLockFile(bPaths);
        string reason;
        if (!checkBuildReady(rdir, bPaths, reason))
        {
            buildPackage(rdir, config, depInfos, absDest);
        }
        return;
    }

    auto config = BuildConfig(profile);
    const buildId = BuildId(rdir.recipe, config, absDest);
    const bPaths = rdir.buildPaths(buildId);
    acquireBuildLockFile(bPaths);

    enforceBuildReady(rdir, bPaths);

    const cwd = getcwd();
    chdir(rdir.root);
    scope(exit)
        chdir(cwd);

    rdir.recipe.stage(bPaths.install, absDest);
}

int stageMain(string[] args)
{
    string profileName;

    // dfmt off
    auto helpInfo = getopt(args,
        "profile|p", "Stage for the given profile.", &profileName,
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

    auto rdir = RecipeDir.enforceFromDir(".");
    auto lock = acquireRecipeLockFile(rdir);

    auto recipe = rdir.recipe;

    const srcDir = enforceSourceReady(rdir, recipe).absolutePath();

    auto profile = enforceProfileReady(rdir, recipe, profileName);

    recipe.revision = calcRecipeRevision(recipe);
    logInfo("%s: %s", info("Revision"), info(recipe.revision));

    DepInfo[string] depInfos;

    if (recipe.hasDependencies)
    {
        auto dag = enforceResolved(rdir);
        auto cache = new PackageCache(homeCacheDir);
        // FIXME: system should be serialized with DAG.
        const system = Yes.system;

        auto service = new DependencyService(cache, null, system);

        depInfos = collectDepInfos(dag, recipe, profile, service, absDest);

        foreach (dn; dag.traverseTopDownResolved())
        {
            auto drdir = service.packRecipe(dn.pack.name, dn.aver, dn.revision);
            auto dprof = profile.subset(drdir.recipe.langs);
            stagePackage(drdir, dprof, absDest, depInfos);
        }
    }

    stagePackage(rdir, profile.subset(recipe.langs), absDest, depInfos);

    logInfo("Stage: %s - %s", success("OK"), info(dest));

    return 0;
}
