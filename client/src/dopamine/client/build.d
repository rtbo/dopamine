module dopamine.client.build;

import dopamine.recipe;

import std.file;
import std.getopt;
import std.stdio;

int buildMain(string[] args)
{
    string changeDir;

    auto helpInfo = getopt(
        args,
        "change-dir|C", &changeDir,
    );

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("Build a package", helpInfo.options);
    }

    if (changeDir.length) {
        writeln("changing current directory to ", changeDir);
        chdir(changeDir);
    }

    if (!exists("dopamine.lua")) {
        throw new Exception("the directory do not have a dopamine.lua file");
    }

    writeln("parsing recipe");
    auto recipe = parseRecipe("dopamine.lua");

    writeln(recipe.copyright);

    return 0;
}
