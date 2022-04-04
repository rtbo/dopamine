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

void enforceBuildReady(RecipeDir rdir, ConfigDir cdir)
{
    enforce(cdir.exists, new FormatLogException(
        "Build: %s - Config directory doesn't exist", error( "NOK")
    ));

    auto lock = acquireConfigLockFile(cdir);
    enforce(cdir.stateFile.exists(), new FormatLogException(
        "Build: %s - Config state file doesn't exist", error("NOK")
    ));

    auto state = cdir.stateFile.read();

    enforce (rdir.recipeLastModified < cdir.stateFile.timeLastModified, new FormatLogException(
        "Build: %s - Config directory is not up-to-date", error("NOK")
    ));

    enforce(rdir.recipeLastModified < state.buildTime, new FormatLogException(
        "Build: %s - Build is not up-to-date", error("NOK")
    ));

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

    const cDir = dir.configDir(config);
    auto cLock = acquireConfigLockFile(cDir);


    auto state = cDir.stateFile.read();

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

    const bdirs = BuildDirs(absolutePath(".", cwd), absolutePath(srcDir, cwd));

    mkdirRecurse(cDir.dir);

    {
        chdir(cDir.dir);
        scope(success)
            chdir(cwd);
        recipe.build(bdirs, config, depInfos);
    }

    state.buildTime = Clock.currTime;

    cDir.stateFile.write(state);

    logInfo("Build: %s", success("OK"));
    return 0;
}
