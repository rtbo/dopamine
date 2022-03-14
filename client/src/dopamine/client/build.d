module dopamine.client.build;

import dopamine.client.profile;
import dopamine.client.source;
import dopamine.client.utils;

import dopamine.log;
import dopamine.paths;

import std.exception;
import std.getopt;


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

    const srcDir = enforceSourceReady(dir, recipe);

    auto profile = enforceProfileReady(dir, recipe, profileName);

    const cDir = dir.configDir(profile);
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

    return 0;
}