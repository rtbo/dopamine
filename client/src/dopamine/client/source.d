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
    const recipe = parseRecipe("dopamine.lua");

    if (!recipe.outOfTree)
    {
        writeln("source integrated to package: nothing to do");
        return 0;
    }

    const previous = readSourceFlagFile();
    if (previous && exists(previous) && isDir(previous))
    {
        writefln("Source was previously extracted to '%s'\nNothing to do.", previous);
        return 0;
    }

    const dest = localSourceDest();

    mkdirRecurse(dest);

    const srcDir = recipe.source.fetch(dest);

    writeSourceFlagFile(srcDir);

    return 0;
}
