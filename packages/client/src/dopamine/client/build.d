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

void enforceBuildReady(RecipeDir rdir, ConfigDirs cdirs)
{
    string reason;
    if (!checkBuildReady(rdir, cdirs, reason))
    {
        throw new FormatLogException(
            "Build: %s - %s. Try to run %s.",
            error("NOK"), reason, info("dop build")
        );
    }

    logInfo("Build: %s", success("OK"));
}

void buildPackage(RecipeDir rdir, Recipe recipe, BuildConfig config, DepInfo[string] depInfos)
{
    string reason;
    const srcDir = enforce(checkSourceReady(rdir, recipe, reason));

    const cdirs = rdir.configDirs(config);

    const cwd = getcwd();

    const root = absolutePath(rdir.dir, cwd);
    const src = absolutePath(srcDir, rdir.dir);
    const bdirs = BuildDirs(root, src, cdirs.installDir);

    mkdirRecurse(cdirs.buildDir);

    {
        chdir(cdirs.buildDir);
        scope(success)
            chdir(cwd);
        recipe.build(bdirs, config, depInfos);
    }

    ConfigState state = cdirs.stateFile.read();
    state.buildTime = Clock.currTime;
    cdirs.stateFile.write(state);
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

    auto profile = enforceProfileReady(rdir, recipe, profileName);

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

    auto config = BuildConfig(profile.subset(recipe.langs));
    if (environment.get("DOP_E2E_TEST_CONFIG"))
    {
        // undocumented env var used to dump the config hash in a file.
        // Used by end-to-end tests to locate build config directory
        write(environment["DOP_E2E_TEST_CONFIG"], config.digestHash);
    }

    const cdirs = rdir.configDirs(config);
    auto cLock = acquireConfigLockFile(cdirs);


    auto state = cdirs.stateFile.read();

    if (!recipe.inTreeSrc && state.buildTime > rdir.recipeLastModified && !force)
    {
        logInfo(
            "%s: Already up-to-date (run with %s to overcome)",
            info("Build"), info("--force")
        );
        return 0;
    }

    destroy(lock);

    buildPackage(rdir, recipe, config, depInfos);

    logInfo("Build: %s", success("OK"));
    return 0;
}
