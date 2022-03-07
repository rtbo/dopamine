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

auto acquireRecipeLockFile(RecipeDir dir)
{
    import dopamine.util : acquireLockFile, tryAcquireLockFile;
    import std.file : mkdirRecurse;
    import std.path : baseName, dirName;

    const path = dir.lockFile;
    mkdirRecurse(dirName(path));
    auto lock = tryAcquireLockFile(path);
    if (lock)
        return lock;

    logInfo("Waiting to acquire recipe lock ", info(path));
    return acquireLockFile(path);
}
