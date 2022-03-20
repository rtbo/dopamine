module dopamine.client.build;

import dopamine.client.profile;
import dopamine.client.source;
import dopamine.client.utils;

import dopamine.build_id;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;

import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.process;

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
    const cDir = dir.configDir(config);
    auto cLock = acquireConfigLockFile(cDir);

    auto stateFile = cDir.stateFile;
    auto state = stateFile.read();

    if (!recipe.inTreeSrc && state.build && !force)
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
    chdir(cDir.dir);

    recipe.build(bdirs, config, null);

    return 0;
}