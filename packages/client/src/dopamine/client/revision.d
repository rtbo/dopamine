module dopamine.client.revision;

import dopamine.client.utils;

import dopamine.log;
import dopamine.paths;
import dopamine.recipe_old;

import std.exception;

int revisionMain(string[] args)
{
    const rdir = RecipeDir.enforced(".");

    auto recipe = parseRecipe(rdir);

    enforce(recipe.isPackage, new ErrorLogException(
            "Light recipes do not have revision"
    ));

    logInfo("%s: %s", info("Revision"), info(calcRecipeRevision(recipe)));

    return 0;
}
