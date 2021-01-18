module dopamine.client.source;

import dopamine.client.recipe;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.state;
import dopamine.util;

import std.getopt;
import std.file;
import std.path;

string enforceSourceReady(PackageDir dir, Recipe recipe)
{
    import std.exception : enforce;

    return enforce(checkSourceReady(dir, recipe), new FormatLogException(
            "%s: Source directory for %s is not ready or not up-to-date. Try to run `%s`.",
            error("Error"), info(recipe.name), info("dop source")));
}

/// dop source command
/// used to download the source of a package
int sourceMain(string[] args)
{
    string dest = ".";
    bool force;

    auto helpInfo = getopt(args, "dest", &dest, "force|f", &force);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop source command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);

    if (recipe.inTreeSrc)
    {
        if (dest)
        {
            logWarning("%s: Ignoring %s for in-tree source", warning("Warning"), info("--dest"));
        }
        logInfo("%s: in-tree at %s - nothing to do", info("Source"), info(recipe.source()));
        return 0;
    }

    if (!exists(dest))
    {
        mkdirRecurse(dest);
    }

    const srcReady = checkSourceReady(dir, recipe);
    if (!force && srcReady)
    {
        logInfo("source already exists at %s", info(srcReady));
        logInfo("use %s to download anyway", info("--force"));
        return 0;
    }

    auto flag = dir.sourceFlag;
    flag.remove();

    auto srcDir = dest.fromDir!(() => recipe.source());
    if (dest == ".")
    {
        srcDir = srcDir.relativePath(dest);
    }
    else
    {
        srcDir = srcDir.absolutePath(dest).relativePath();
    }

    flag.write(srcDir);
    logInfo("%s: %s - %s", info("Source"), success("OK"), srcDir);

    return 0;
}
