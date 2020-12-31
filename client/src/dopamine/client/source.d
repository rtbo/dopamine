module dopamine.client.source;

import dopamine.client.util;

import dopamine.paths;
import dopamine.recipe;
import dopamine.source;
import dopamine.state;

import std.file;
import std.stdio;

SourceState enforcedSourceState(PackageDir dir, const(Recipe) recipe)
{
    return new EnforcedSourceState(dir, recipe,
            "Source code not available or not up-to-date. Try to run `dop source`");
}

int sourceMain(string[] args)
{
    const packageDir = PackageDir.enforced(".");

    const recipe = parseRecipe(packageDir);

    if (!recipe.outOfTree)
    {
        writeln("source integrated to package: nothing to do");
        return 0;
    }

    auto state = new FetchSourceState(packageDir, recipe);

    if (state.reached)
    {
        writefln("Source was previously extracted to '%s'\nNothing to do.", state.sourceDir);
    }
    else
    {
        state.reach();
    }

    return 0;
}
