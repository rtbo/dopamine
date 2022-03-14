module dopamine.client.source;

import dopamine.client.utils;

import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.util;

import std.getopt;
import std.file;
import std.path;

string enforceSourceReady(RecipeDir dir, Recipe recipe)
{
    if (recipe.inTreeSrc)
    {
        const srcDir = recipe.source();
        auto state = dir.stateFile.read();
        state.srcDir = srcDir;
        dir.stateFile.write(state);
        return srcDir;
    }

    auto sf = dir.stateFile;
    auto state = sf.read();
    if (!sf || !state.srcDir)
    {
        throw new ErrorLogException(
            "Source directory is not ready. Run %s.",
            info("dop source"),
        );
    }

    if (sf.timeLastModified > dir.recipeLastModified)
    {
        throw new ErrorLogException(
            "Source directory is not up-to-date. Run %s.",
            info("dop source"),
        );
    }

    return state.srcDir;
}

int sourceMain(string[] args)
{
    bool force;

    auto helpInfo = getopt(args, "force|f", &force);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop source command", helpInfo.options);
        return 0;
    }

    const dir = RecipeDir.enforced(".");
    auto recipe = parseRecipe(dir);

    if (recipe.inTreeSrc)
    {
        logInfo("%s: in-tree at %s - nothing to do", info("Source"), info(
                absolutePath(recipe.source())));
    }

    auto lock = acquireRecipeLockFile(dir);
    auto stateFile = dir.stateFile();

    auto state = stateFile.read();

    if (!force && state.srcDir && exists(state.srcDir))
    {
        logInfo("source already exists at %s", info(state.srcDir));
        logInfo("use %s to download anyway", info("--force"));
        return 0;
    }

    state.srcDir = recipe.source();

    stateFile.write(state);

    logInfo("%s: %s - %s", info("Source"), success("OK"), state.srcDir);

    return 0;
}
