module dopamine.client.revision;

import dopamine.client.utils;

import dopamine.log;
import dopamine.recipe;

import std.exception;

int revisionMain(string[] args)
{
    auto rdir = enforceRecipe(".");

    enforce(!rdir.recipe.isDub, new ErrorLogException(
            "Dub packages do not have revision"
    ));
    enforce(!rdir.recipe.isLight, new ErrorLogException(
            "Light recipes do not have revision"
    ));

    logInfo("%s: %s", info("Revision"), info(rdir.calcRecipeRevision()));

    return 0;
}
