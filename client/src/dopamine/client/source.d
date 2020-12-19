module dopamine.client.source;

import dopamine.paths;
import dopamine.recipe;
import dopamine.source;
import dopamine.state;

import std.file;
import std.stdio;

int sourceMain(string[] args)
{
    const packageDir = PackageDir.enforced(".");

    writeln("parsing recipe");
    const recipe = recipeParseFile(packageDir.dopamineFile());

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
