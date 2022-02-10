module test.util;

import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.file;
import std.path;

string testPath(Args...)(Args args)
{
    return buildNormalizedPath(dirName(__FILE_FULL_PATH__), args);
}

/// execute pred from directory dir
/// and chdir back to the previous dir afterwards
/// Returns: whatever pred returns
deprecated("not reentrant helper function")
auto fromDir(alias pred)(string dir) @system
{
    // shortcut if chdir is not needed
    if (dir == ".")
        return pred();

    const cwd = getcwd();
    chdir(dir);
    scope (exit)
        chdir(cwd);

    return pred();
}
