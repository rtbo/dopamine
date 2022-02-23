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
