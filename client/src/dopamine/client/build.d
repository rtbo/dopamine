module dopamine.client.build;

import dopamine.client.profile;
import dopamine.client.resolve;
import dopamine.client.source;
import dopamine.client.utils;

import dopamine.build_id;
import dopamine.dep.dag;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.state;

import std.datetime;
import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.process;

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

int buildMain(string[] args)
{
    string profileName;
    bool force;
    bool noNetwork;

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

    const dir = RecipeDir.enforced(".");
    auto lock = acquireRecipeLockFile(dir);

    auto recipe = parseRecipe(dir);

    const srcDir = enforceSourceReady(dir, recipe).absolutePath();

    auto profile = enforceProfileReady(dir, recipe, profileName);

    auto config = BuildConfig(profile);
    if (environment.get("DOP_E2E_TEST_CONFIG"))
    {
        // undocumented env var used to dump the config hash in a file.
        // Used by end-to-end tests to locate build config directory
        write(environment["DOP_E2E_TEST_CONFIG"], config.digestHash);
    }

    DepInfo[string] depInfos;
    if (recipe.hasDependencies)
    {
        auto dag = enforceResolved(dir);
        foreach (dep; dag.traverseBottomUpResolved)
        {
            // build if not done
            // collect DepInfo
        }
    }

    const cdirs = dir.configDirs(config);
    auto cLock = acquireConfigLockFile(cdirs);


    auto state = cdirs.stateFile.read();

    if (!recipe.inTreeSrc && state.buildTime > dir.recipeLastModified && !force)
    {
        logInfo(
            "%s: Already up-to-date (run with %s to overcome)",
            info("Build"), info("--force")
        );
        return 0;
    }

    destroy(lock);

    const cwd = getcwd();

    const root = absolutePath(".", cwd);
    const src = absolutePath(srcDir, cwd);
    const bdirs = BuildDirs(root, src, cdirs.installDir);

    mkdirRecurse(cdirs.buildDir);

    {
        chdir(cdirs.buildDir);
        scope(success)
            chdir(cwd);
        recipe.build(bdirs, config, depInfos);
    }

    state.buildTime = Clock.currTime;

    cdirs.stateFile.write(state);

    logInfo("Build: %s", success("OK"));
    return 0;
}
