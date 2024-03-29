module dopamine.client.source;

import dopamine.client.utils;

import dopamine.log;
import dopamine.recipe;
import dopamine.util;

import std.getopt;
import std.file;
import std.path;

string enforceSourceReady(RecipeDir rdir)
{
    import std.exception : enforce;

    string reason;
    string srcDir = rdir.checkSourceReady(reason);
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

    auto rdir = enforceRecipe();
    auto recipe = rdir.recipe;

    if (recipe.inTreeSrc)
    {
        logInfo("%s: in-tree at %s - nothing to do", info("Source"), info(
                absolutePath(recipe.source())));
    }

    auto lock = acquireRecipeLockFile(rdir);
    auto stateFile = rdir.stateFile();

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
