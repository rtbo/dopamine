module dopamine.client.source;

import dopamine.client.utils;

import dopamine.log;
import dopamine.paths;

import std.path;

int sourceMain(string[] args)
{
    const dir = RecipeDir.enforced(".");
    auto recipe = parseRecipe(dir);

    if (recipe.inTreeSrc)
    {
        logInfo("%s: in-tree at %s - nothing to do", info("Source"), info(absolutePath(recipe.source())));
    }

    return 0;
}
