module dopamine.client.revision;

import dopamine.client.utils;

import dopamine.log;
import dopamine.recipe;

import std.exception;

int revisionMain(string[] args)
{
    auto rdir = RecipeDir.enforceFromDir(".");

    enforce(rdir.recipe.isPackage, new ErrorLogException(
            "Light recipes do not have revision"
    ));

    rdir.calcRecipeRevision();
    logInfo("%s: %s", info("Revision"), info(rdir.recipe.revision));

    return 0;
}
