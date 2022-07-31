module dopamine.cache_dirs;

import dopamine.semver;

import std.exception;
import std.file;
import std.path;

@safe:

struct CachePackageDir
{
    mixin CacheDir!();

    @property string name() const
    {
        return baseName(_dir);
    }

    @property string cacheDir() const
    {
        return dirName(_dir);
    }

    CacheVersionDir versionDir(string ver) const
    in (Semver.isValid(ver))
    {
        const verDir = buildPath(_dir, ver);
        return CacheVersionDir(verDir);
    }

    CacheVersionDir versionDir(Semver ver) const
    {
        return versionDir(ver.toString());
    }

    auto versionDirs() const @trusted
    {
        import std.algorithm : map;

        return dirInputRange(_dir).map!(vd => CacheVersionDir(vd));
    }
}

struct CacheVersionDir
{
    mixin CacheDir!();

    @property string ver() const @safe
    {
        return baseName(_dir);
    }

    @property Semver semver() const @safe
    {
        return Semver(ver);
    }

    @property string cacheDir() const @safe
    {
        return packageDir.cacheDir;
    }

    @property CachePackageDir packageDir() const @safe
    {
        return CachePackageDir(dirName(_dir));
    }

    @property string packageName() const @safe
    {
        return baseName(dirName(_dir));
    }

    @property string dubLockFile() const @safe
    {
        return _dir ~ ".lock";
    }

    CacheRevisionDir dopRevisionDir(string rev) const @safe
    {
        const revDir = buildPath(_dir, rev);
        return CacheRevisionDir(revDir);
    }

    auto dopRevisionDirs() const @trusted
    {
        import std.algorithm : filter, map;

        return dirInputRange(_dir)
            .map!(rd => CacheRevisionDir(rd))
            .filter!(rd => rd.exists);
    }
}

struct CacheRevisionDir
{
    private string _dir;

    this(string dir) @safe
    {
        enforce(!stdExists(dir) || isDir(dir));
        _dir = dir;
    }

    @property string dir() const @safe
    {
        return _dir;
    }

    @property string revision() const @safe
    {
        return baseName(_dir);
    }

    @property string cacheDir() const @safe
    {
        return versionDir.cacheDir;
    }

    @property CachePackageDir packageDir() const @safe
    {
        return versionDir.packageDir;
    }

    @property CacheVersionDir versionDir() const @safe
    {
        return CacheVersionDir(dirName(_dir));
    }

    @property bool exists() const @safe
    {
        return stdExists(recipeFile);
    }

    bool opCast(T : bool)() const @safe
    {
        return this.exists;
    }

    @property string recipeFile() const @safe
    {
        return buildPath(_dir, "dopamine.lua");
    }

    @property string lockFile() const @safe
    {
        return _dir ~ ".lock";
    }
}

private alias stdExists = std.file.exists;

private mixin template CacheDir()
{
    private string _dir;

    this(string dir)
    {
        enforce(!stdExists(dir) || isDir(dir));
        _dir = dir;
    }

    @property string dir() const
    {
        return _dir;
    }

    string opCast(T : string)() const
    {
        return _dir;
    }

    @property bool exists() const
    {
        return stdExists(_dir);
    }

    bool opCast(T : bool)() const
    {
        return this.exists;
    }

    string path(Args...)(Args args) const
    {
        return buildPath(dir, args);
    }
}

package(dopamine) auto dirInputRange(string parent) @trusted
{
    import std.algorithm : filter, map;

    return dirEntries(parent, SpanMode.shallow)
        .filter!(e => e.isDir)
        .map!(e => e.name);
}
