module dopamine.client.revision;

import dopamine.client.utils;

import dopamine.log;
import dopamine.recipe;

import std.exception;

int revisionMain(string[] args)
{
    auto rdir = RecipeDir.enforceFromDir(".");

    auto recipe = rdir.recipe;

    enforce(recipe.isPackage, new ErrorLogException(
            "Light recipes do not have revision"
    ));

    logInfo("%s: %s", info("Revision"), info(calcRecipeRevision(recipe)));

    return 0;
}
