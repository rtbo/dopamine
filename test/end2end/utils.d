module utils;

import std.algorithm;
import std.exception;
import std.file;
import std.path;
import std.process;
import std.stdio;
import std.string;

string testName()
{
    return baseName(stripExtension(thisExePath()));
}

string recipesDir()
{
    return buildNormalizedPath(__FILE_FULL_PATH__.dirName, "recipes");
}

string recipeDir(string recipeName)
{
    return buildPath(recipesDir(), recipeName);
}

int drive(void delegate() driver)
{
    try
    {
        driver();
        return 0;
    }
    catch (Exception ex)
    {
        stderr.writefln("Test %s failed: %s", testName, ex.msg);
    }
    return 1;
}

void assertCommandOutput(string[] cmd, string[] texts)
{
    auto res = execute(cmd);
    enforce(res.status == 0, format("Command `%s` failed with code %s",
            escapeShellCommand(cmd), res.output));
    foreach (text; texts)
    {
        enforce(res.output.canFind(text), format("\"%s\" not found in command output:\n%s\n%s",
                text, escapeShellCommand(cmd), res.output));
    }
}
