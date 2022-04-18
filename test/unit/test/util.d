module test.util;

import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.file;
import std.path;

import core.sync.mutex;

string testPath(Args...)(Args args)
{
    return buildNormalizedPath(dirName(__FILE_FULL_PATH__), args);
}

struct DeleteMe
{
    string path;

    this(string basename, string ext)
    {
        import dopamine.util : tempPath;

        path = tempPath(null, basename, ext);
    }

    ~this()
    {
        import std.file : exists, isDir, remove, rmdirRecurse;

        if (exists(path))
        {
            if (isDir(path))
                rmdirRecurse(path);
            else
                remove(path);
        }
    }
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
