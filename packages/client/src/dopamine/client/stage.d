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

void stagePackage(Recipe recipe, Profile profile, string absDest, DepInfo[string] depInfos)
in(isAbsolute(absDest))
{
    const rdir = RecipeDir.enforced(dirName(recipe.filename));
    if (recipe.stageFalse)
    {
        const config = BuildConfig(profile);
        const buildId = BuildId(recipe, config, absDest);
        const bPaths = BuildPaths(rdir, buildId);
        acquireBuildLockFile(bPaths);
        string reason;
        if (!checkBuildReady(rdir, bPaths, reason))
        {
            buildPackage(rdir, recipe, config, depInfos, absDest);
        }
        return;
    }

    auto config = BuildConfig(profile);
    const buildId = BuildId(recipe, config, absDest);
    const bPaths = BuildPaths(rdir, buildId);
    acquireBuildLockFile(bPaths);

    enforceBuildReady(rdir, bPaths);

    const cwd = getcwd();
    scope(exit)
        chdir(cwd);

    if (recipe.hasFunction("stage"))
    {
        chdir(bPaths.install);
        recipe.stage(absDest);
    }
    else
    {
        installRecurse(bPaths.install, absDest);
    }

    if (recipe.hasFunction("post_stage"))
    {
        chdir(absDest);
        recipe.postStage();
    }
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

    const rdir = RecipeDir.enforced(".");
    auto lock = acquireRecipeLockFile(rdir);

    auto recipe = parseRecipe(rdir);

    const srcDir = enforceSourceReady(rdir, recipe).absolutePath();

    auto profile = enforceProfileReady(rdir, recipe, profileName);

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
            auto drec = service.packRecipe(dn.pack.name, dn.aver, dn.revision);
            auto dprof = profile.subset(drec.langs);
            stagePackage(drec, dprof, absDest, depInfos);
        }
    }

    stagePackage(recipe, profile.subset(recipe.langs), absDest, depInfos);

    logInfo("Stage: %s - %s", success("OK"), info(dest));

    return 0;
}
