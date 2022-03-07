module dopamine.client.source;

import dopamine.client.utils;

import dopamine.paths;

int sourceMain(string[] args)
{
    const dir = RecipeDir.enforced(".");
    auto recipe = parseRecipe(dir);

    return 0;
}
