module test.util;

import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.file;
import std.path;
import std.string;

import core.sync.mutex;

string testPath(Args...)(Args args)
{
    return buildNormalizedPath(dirName(__FILE_FULL_PATH__), args);
}

/// Generate a unique name for temporary path (either dir or file)
/// Params:
///     location = some directory to place the file in. If omitted, std.file.tempDir is used
///     prefix = prefix to give to the base name
///     ext = optional extension to append to the path (must contain '.')
/// Returns: a path (i.e. location/prefix-{uniquestring}.ext)
string tempPath(string location = null, string prefix = null, string ext = null)
in (!location || (exists(location) && isDir(location)))
in (!ext || ext.startsWith('.'))
out (res; (!location || res.startsWith(location)) && !exists(res))
{
    import std.array : array;
    import std.path : buildPath;
    import std.random : Random, unpredictableSeed, uniform;
    import std.range : generate, only, takeExactly;

    auto rnd = Random(unpredictableSeed);

    if (prefix)
        prefix ~= "-";

    if (!location)
        location = tempDir;

    string res;
    do
    {
        const basename = prefix ~ generate!(() => uniform!("[]")('a', 'z',
                rnd)).takeExactly(10).array ~ ext;

        res = buildPath(location, basename);
    }
    while (exists(res));

    return res;
}

/// Execute pred from directory dir and chdir back
/// to the previous dir afterwards.
///
/// As tests are often run in parallel, a global lock
/// is acquired during exectution of pred.
/// Note: this function should be the single entry point for chdir for tests.
///
/// Returns: whatever pred returns
auto fromDir(alias pred)(string dir) @system
{
    cwdLock.lock();
    scope (exit)
        cwdLock.unlock();

    // shortcut if chdir is not needed
    if (dir == ".")
        return pred();

    const cwd = getcwd();
    chdir(dir);
    scope (exit)
        chdir(cwd);

    return pred();
}

private __gshared Mutex cwdLock;

shared static this()
{
    cwdLock = new Mutex();
}
