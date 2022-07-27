module dopamine.client.utils;

import dopamine.log;
import dopamine.recipe;

import std.array;
import std.exception;
import std.file;
import std.path;
import std.process;
import std.string;

enum Cvs
{
    none,
    git,
    hg,
}

Cvs getCvs(string dir=getcwd())
{
    dir = buildNormalizedPath(absolutePath(dir));

    while (true)
    {
        const git = buildPath(dir, ".git");
        if (exists(git) && isDir(git))
            return Cvs.git;

        const hg = buildPath(dir, ".hg");
        if (exists(hg) && isDir(hg))
            return Cvs.hg;

        string parent = dirName(dir);
        if (parent == dir)
            return Cvs.none;

        dir = parent;
    }
}

bool isRepoClean(Cvs cvs, string dir = getcwd())
in (cvs != Cvs.none)
{
    import std.array;

    const cmd = cvs == Cvs.git ?
        ["git", "status", "--porcelain"] : ["hg", "status"];

    const res = execute(cmd, null, Config.none, size_t.max, dir);
    enforce(
        res.status == 0,
        new ErrorLogException("Could not run %s: %s", info(cmd.join(" ")), res.output)
    );
    return res.output.strip().length == 0;
}

private auto acquireSomeLockFile(string path, string desc)
{
    import dopamine.util : acquireLockFile, tryAcquireLockFile;

    mkdirRecurse(dirName(path));
    auto lock = tryAcquireLockFile(path);
    if (lock)
        return lock;

    logInfo("Waiting to acquire %s lock %s", desc, info(path));
    return acquireLockFile(path);
}

auto acquireRecipeLockFile(RecipeDir dir)
{
    return acquireSomeLockFile(dir.lockFile, "recipe");
}

auto acquireBuildLockFile(BuildPaths bPaths)
{
    return acquireSomeLockFile(bPaths.lock, "build");
}
