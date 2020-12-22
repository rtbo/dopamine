module dopamine.client.util;

import dopamine.log;
import dopamine.paths;
import dopamine.recipe;

const(Recipe) parseRecipe(PackageDir packageDir)
{
    const recipe = recipeParseFile(packageDir.dopamineFile());
    logInfo("%s: %s - %s-%s", info("Recipe"), success("OK"), recipe.name, recipe.ver);
    return recipe;
}
