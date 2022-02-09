module dopamine.client.utils;

import dopamine.log;
import dopamine.paths;
import dopamine.recipe;

Recipe parseRecipe(PackageDir dir)
{
    auto recipe = Recipe.parseFile(dir.dopamineFile());
    logInfo("%s: %s - %s-%s", info("Recipe"), success("OK"), recipe.name, recipe.ver);
    return recipe;
}
