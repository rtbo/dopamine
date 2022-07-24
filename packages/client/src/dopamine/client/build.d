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
import dopamine.state;

import std.datetime;
import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.process;
import std.typecons;

void enforceBuildReady(RecipeDir rdir, BuildPaths bPaths)
{
    string reason;
    if (!checkBuildReady(rdir, bPaths, reason))
    {
        throw new FormatLogException(
            "Build: %s - %s. Try to run %s.",
            error("NOK"), reason, info("dop build")
        );
    }

    logInfo("%s: %s", info("Build"), success("OK"));
}

string buildPackage(
    const(RecipeDir) rdir,
    Recipe recipe,
    const(BuildConfig) config,
    DepInfo[string] depInfos,
    string stageDest = null)
{
    string reason;
    const srcDir = enforce(checkSourceReady(rdir, recipe, reason));

    const buildId = BuildId(recipe, config, stageDest);
    const bPaths = BuildPaths(rdir, buildId);

    const cwd = getcwd();

    const root = absolutePath(rdir.dir, cwd);
    const src = absolutePath(srcDir, rdir.dir);
    const bdirs = BuildDirs(root, src, stageDest ? stageDest : bPaths.install);

    mkdirRecurse(bPaths.build);

    {
        chdir(bPaths.build);
        scope (success)
            chdir(cwd);
        recipe.build(bdirs, config, depInfos);
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

    const rdir = RecipeDir.enforced(".");
    auto lock = acquireRecipeLockFile(rdir);

    auto recipe = parseRecipe(rdir);

    const srcDir = enforceSourceReady(rdir, recipe).absolutePath();

    const profile = enforceProfileReady(rdir, recipe, profileName);

    recipe.revision = calcRecipeRevision(recipe);
    logInfo("%s: %s", info("Revision"), info(recipe.revision));

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

    const bPaths = BuildPaths(rdir, buildId);
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

    const dir = buildPackage(rdir, recipe, config, depInfos);

    logInfo("%s: %s - %s", info("Build"), success("OK"), dir);

    return 0;
}
