module dopamine.client.source;

import dopamine.client.utils;

import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.util;
import dopamine.state;

import std.getopt;
import std.file;
import std.path;

string enforceSourceReady(RecipeDir dir, Recipe recipe)
{
    import std.exception : enforce;

    string reason;
    string srcDir = checkSourceReady(dir, recipe, reason);
    enforce(srcDir, new ErrorLogException("%s. Try to run %s", reason, info("dop source")));
    logInfo("%s: %s - %s", info("Source"), success("OK"), srcDir);
    return srcDir;
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
