module dopamine.client.source;

import dopamine.client.util;

import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.source;
import dopamine.state;

string enforceSourceDirReady(PackageDir dir, const(Recipe) recipe)
{
    import std.exception : enforce;

    return enforce(checkSourceReady(dir, recipe), new FormatLogException(
            "%s: Source directory for %s is not ready or not up-to-date. Try to run `%s`.",
            error("Error"), info(recipe.name), info("dop source")));
}

string prepareSourceDir(PackageDir dir, const(Recipe) recipe)
{
    return recipe.source.fetch(dir);
}

int sourceMain(string[] args)
{
    const dir = PackageDir.enforced(".");

    const recipe = parseRecipe(dir);

    if (!recipe.outOfTree)
    {
        logInfo("Source integrated to package: nothing to do");
        return 0;
    }

    auto sourceDir = checkSourceReady(dir, recipe);

    if (sourceDir)
    {
        logInfo("Source was previously extracted to '%s'\nNothing to do.", sourceDir);
    }
    else
    {
        sourceDir = prepareSourceDir(dir, recipe);
        logInfo("Source extracted to '%s'", info(sourceDir));

    }

    return 0;
}
