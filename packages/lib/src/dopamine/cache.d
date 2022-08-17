module dopamine.cache;

import dopamine.api.v1;
import dopamine.log;
import dopamine.recipe;
import dopamine.registry;
import dopamine.semver;
import dopamine.util;

import squiz_box;

import std.array;
import std.digest.sha;
import std.exception;
import std.file;
import std.path;
import std.range;

@safe:

/// A local package cache
class PackageCache
{
    private string _dir;

    /// Construct a cache in the specified directory.
    /// [dir] would typically be "~/.dop/cache" on Linux and "%LOCALAPPDATA%\dop\cache" on Windows.
    this(string dir)
    {
        _dir = dir;
    }

    /// Get an InputRange of CachePackageDir of all packages in the cache.
    /// Throws: FileException if the cache directory does not exist
    auto packageDirs() const @trusted
    {
        import std.algorithm : map;

        return dirInputRange(_dir)
            .map!(d => CachePackageDir(d));
    }

    /// Get a CachePackageDir for the package [packname]
    CachePackageDir packageDir(string packname) const
    {
        return CachePackageDir(buildPath(_dir, packname));
    }

    CacheRevisionDir cacheRecipe(Registry registry,
        const ref PackageResource pack,
        string ver,
        string revision = null) @trusted
    out (res; res.exists)
    {
        import std.algorithm : canFind, each, map;
        import std.conv : to;
        import std.format : format;
        import std.stdio : File;

        if (revision)
        {
            const revDir = packageDir(pack.name).versionDir(ver).dopRevisionDir(revision);
            if (revDir && checkDopRecipeFile(revDir.dir))
            {
                return revDir;
            }

            logInfo("Fetching recipe %s/%s/%s from registry", info(pack.name), info(ver), info(
                    revision));
        }
        else
        {
            logInfo("Fetching recipe %s/%s latest revision from registry", info(pack.name), info(
                    ver));
        }

        Response!PackageRecipeResource resp;
        if (revision)
            resp = registry.sendRequest(GetPackageRecipe(pack.name, ver, revision));
        else
            resp = registry.sendRequest(GetPackageLatestRecipe(pack.name, ver));

        enforce(resp.code < 400, new ErrorLogException(
                "Could not fetch %s/%s%s%s: registry returned %s",
                info(pack.name), info(ver), revision ? "/" : "", info(revision ? revision : ""),
                error(resp.code.to!string)
        ));

        const res = resp.payload;

        enforce(res.ver == ver, new Exception(
                "Registry returned a package version that do not match request:\n" ~
                format("  - requested %s/%s\n", pack.name, ver) ~
                format("  - obtained %s/%s", pack.name, res.ver)
        ));

        if (revision)
            enforce(res.revision == revision, new Exception(
                    "Registry returned a revision that do not match request"
            ));
        else
            revision = res.revision;

        const archiveName = res.archiveName;
        const filename = buildPath(tempDir(), archiveName);
        registry.downloadArchive(archiveName, filename);

        scope (exit)
            remove(filename);

        auto revDir = packageDir(pack.name)
            .versionDir(res.ver)
            .dopRevisionDir(res.revision);

        mkdirRecurse(revDir.versionDir.dir);

        auto lock = File(revDir.lockFile, "w");
        lock.lock();

        mkdirRecurse(revDir.dir);

        readBinaryFile(filename)
            .unboxTarXz()
            .each!(e => e.extractTo(revDir.dir));

        enforce(
            checkDopRecipeFile(revDir.dir),
            "Could not find recipe file after extracting recipe archive at " ~ revDir.dir
        );

        return revDir;
    }
}

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
