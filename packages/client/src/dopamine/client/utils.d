module dopamine.client.utils;

import dopamine.log;
import dopamine.paths;
import dopamine.recipe;

Recipe parseRecipe(RecipeDir dir)
{
    import std.format : format;

    auto recipe = Recipe.parseFile(dir.recipeFile());

    string namever;
    if (!recipe.isLight)
        namever = format(" - %s-%s", recipe.name, recipe.ver);

    logInfo("%s: %s%s", info("Recipe"), success("OK"), namever);
    return recipe;
}

private auto acquireSomeLockFile(string path, string desc)
{
    import dopamine.util : acquireLockFile, tryAcquireLockFile;
    import std.file : mkdirRecurse;
    import std.path : dirName;

    mkdirRecurse(dirName(path));
    auto lock = tryAcquireLockFile(path);
    if (lock)
        return lock;

    logInfo("Waiting to acquire %s lock %s", desc, info(path));
    return acquireLockFile(path);
}

auto acquireRecipeLockFile(RecipeDir dir)
{
    return acquireSomeLockFile(dir.lockPath, "recipe");
}

auto acquireConfigLockFile(ConfigDirs cdirs)
{
    return acquireSomeLockFile(cdirs.lockPath, "config build");
}
