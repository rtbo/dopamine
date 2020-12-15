module dopamine.client.source;

import dopamine.paths;
import dopamine.recipe;
import dopamine.source;

import std.file;
import std.stdio;

int sourceMain(string[] args)
{
    enforcePackageDefinitionDir();

    writeln("parsing recipe");
    const recipe = recipeParseFile("dopamine.lua");

    if (!recipe.outOfTree)
    {
        writeln("source integrated to package: nothing to do");
        return 0;
    }

    auto flagFile = sourceFlagFile(".");

    const previous = flagFile.read();
    if (previous && exists(previous) && isDir(previous))
    {
        writefln("Source was previously extracted to '%s'\nNothing to do.", previous);
        return 0;
    }

    const dest = localSourceDest(".");

    mkdirRecurse(dest);

    const srcDir = recipe.source.fetch(dest);

    flagFile.write(srcDir);

    return 0;
}
