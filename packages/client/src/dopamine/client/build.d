module dopamine.client.build;

import dopamine.client.profile;
import dopamine.client.resolve;
import dopamine.client.source;
import dopamine.client.utils;

import dopamine.build_id;
import dopamine.cache;
import dopamine.dep.build;
import dopamine.dep.dag;
import dopamine.dep.service;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.registry;

import std.datetime;
import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.process;
import std.typecons;

void enforceBuildReady(RecipeDir rdir, BuildId buildId)
{
    string reason;
    if (!rdir.checkBuildReady(buildId, reason))
    {
        throw new FormatLogException(
            "Build: %s - %s. Try to run %s.",
            error("NOK"), reason, info("dop build")
        );
    }

    logInfo("%s: %s", info("Build"), success("OK"));
}

string buildPackage(
    RecipeDir rdir,
    const(BuildConfig) config,
    DepInfo[string] depInfos,
    string stageDest = null)
in (rdir.isAbsolute)
{
    const srcDir = enforceSourceReady(rdir);

    const buildId = BuildId(rdir.recipe, config, stageDest);
    const bPaths = rdir.buildPaths(buildId);

    const cwd = getcwd();

    const root = absolutePath(rdir.root, cwd);
    const src = rdir.path(srcDir);
    const bdirs = BuildDirs(root, src, bPaths.build, stageDest ? stageDest : bPaths.install);

    mkdirRecurse(bPaths.build);

    {
        chdir(bPaths.build);
        scope (success)
            chdir(cwd);
        rdir.recipe.build(bdirs, config, depInfos);
    }

    BuildState state = bPaths.stateFile.read();
    state.buildTime = Clock.currTime;
    bPaths.stateFile.write(state);

    return bPaths.install;
}

int buildMain(string[] args)
{
    string profileName;
    bool force;
    bool noNetwork;
    bool noSystem;

    // dfmt off
    auto helpInfo = getopt(args,
        "profile|p",    &profileName,
        "no-network|N", &noNetwork,
        "force|f",      &force,
    );
    // dfmt on

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop build command", helpInfo.options);
        return 0;
    }

    auto rdir = enforceRecipe(".");
    auto lock = acquireRecipeLockFile(rdir);

    auto recipe = rdir.recipe;

    enforce(!recipe.isLight, new ErrorLogException(
            "Light recipes can't be built by dopamine"
    ));

    const srcDir = enforceSourceReady(rdir).absolutePath();

    const profile = enforceProfileReady(rdir, profileName);

    if (rdir.recipe.isDop)
        logInfo("%s: %s", info("Revision"), info(rdir.calcRecipeRevision()));

    DepInfo[string] depInfos;
    if (recipe.hasDependencies)
    {
        auto dag = enforceResolved(rdir);
        auto cache = new PackageCache(homeCacheDir);
        auto registry = noNetwork ? null : new Registry();
        const system = Yes.system;

        auto service = new DependencyService(cache, registry, system);
        depInfos = buildDependencies(dag, recipe, profile, service);
    }

    const config = BuildConfig(profile.subset(recipe.langs));
    const buildId = BuildId(recipe, config);

    if (environment.get("DOP_E2ETEST_BUILDID"))
    {
        // undocumented env var used to dump the config hash in a file.
        // Used by end-to-end tests to locate build config directory
        write(environment["DOP_E2ETEST_BUILDID"], buildId.toString());
    }

    const bPaths = rdir.buildPaths(buildId);
    auto bLock = acquireBuildLockFile(bPaths);

    auto state = bPaths.stateFile.read();

    if (!recipe.inTreeSrc && state.buildTime > rdir.recipeLastModified && !force)
    {
        logInfo(
            "%s: Already up-to-date (run with %s to overcome)",
            info("Build"), info("--force")
        );
        return 0;
    }

    destroy(lock);

    const dir = buildPackage(rdir.asAbsolute(), config, depInfos);

    logInfo("%s: %s - %s", info("Build"), success("OK"), dir);

    return 0;
}
