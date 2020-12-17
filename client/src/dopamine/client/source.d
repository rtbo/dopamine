module dopamine.client.source;

import dopamine.paths;
import dopamine.recipe;
import dopamine.source;

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

    auto flagFile = packageDir.sourceFlag();

    const previous = flagFile.read();
    if (previous && exists(previous) && isDir(previous))
    {
        writefln("Source was previously extracted to '%s'\nNothing to do.", previous);
        return 0;
    }

    const dest = packageDir.sourceDest();

    mkdirRecurse(dest);

    const srcDir = recipe.source.fetch(dest);

    flagFile.write(srcDir);

    return 0;
}
