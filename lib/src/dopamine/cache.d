module dopamine.cache;

import dopamine.log;
import dopamine.paths;
import dopamine.registry;
import dopamine.semver;

import std.exception;
import std.file;
import std.path;

/// A local package cache
class PackageCache
{
    private string _dir;

    /// Construct a cache in the specified directory.
    /// [dir] wouldt typically be "~/.dop/cache" on Linux and "%LOCALAPPDATA%\dop\cache" on Windows.
    this(string dir)
    {
        _dir = dir;
    }

    /// Get an InputRange of CachePackageDir of all packages in the cache.
    /// Throws: FileException if the cache directory does not exist
    auto packageDirs() const
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

    CacheRevisionDir cacheRecipe(Registry registry, const ref PackagePayload pack, string ver, string revision=null)
    out(res; res.exists)
    {
        import std.algorithm : canFind, map;
        import std.conv : to;
        import std.stdio : File;

        if (revision)
        {
            const revDir = packageDir(pack.name).versionDir(ver).revisionDir(revision);
            if (revDir && revDir.recipeDir.hasRecipeFile)
            {
                return revDir;
            }

            logInfo("Fetching recipe %s/%s/%s from registry", info(pack.name), info(ver), info(revision));
        }
        else {
            logInfo("Fetching recipe %s/%s from registry", info(pack.name), info(ver));
        }

        auto resp = registry.getRecipe(PackageRecipeGet(pack.id, ver, revision));
        enforce(resp.code < 400, new ErrorLogException(
            "Could not fetch %s/%s%s%s: registry returned %s",
            info(pack.name), info(ver), revision ? "/" : "", info(revision ? revision : ""),
            error(resp.code.to!string)
        ));

        enforce(resp.payload.name == pack.name, new Exception(
            "Registry returned a package that do not match request"
        ));

        enforce(resp.payload.ver == ver, new Exception(
            "Registry returned a package version that do not match request"
        ));

        if (revision)
            enforce(resp.payload.rev == revision, new Exception(
                "Registry returned a revision that do not match request"
            ));
        else
            revision = resp.payload.rev;

        enforce(resp.payload.fileList.length >= 1, new Exception(
            "Registry returned a recipe without file"
        ));
        enforce(resp.payload.fileList.map!(rf => rf.name).canFind("dopamine.lua"), new Exception(
            "Registry returned a recipe without main recipe file"
        ));

        auto revDir = packageDir(resp.payload.name)
                .versionDir(resp.payload.ver)
                .revisionDir(resp.payload.rev);

        mkdirRecurse(revDir.versionDir.dir);

        auto lock = File(revDir.lockFile, "w");
        lock.lock();

        mkdirRecurse(revDir.dir);
        auto recDir = cast(RecipeDir)revDir;

        if (resp.payload.fileList.length == 1)
        {
            write(recDir.recipeFile, resp.payload.recipe);
        }
        else {
            assert(false, "unimplemented");
        }

        return revDir;
    }
}

struct CachePackageDir
{
    mixin CacheDir!();

    bool opCast(T : bool)() const
    {
        return stdExists(_dir);
    }

    @property string name() const
    {
        return baseName(_dir);
    }

    @property string cacheDir() const
    {
        return dirName(_dir);
    }

    CacheVersionDir versionDir(string ver)
    in (Semver.isValid(ver))
    {
        const verDir = buildPath(_dir, ver);
        return CacheVersionDir(verDir);
    }

    CacheVersionDir versionDir(Semver ver)
    {
        return versionDir(ver.toString());
    }

    auto versionDirs() const
    {
        import std.algorithm : map;

        return dirInputRange(_dir).map!(vd => CacheVersionDir(vd));
    }
}

struct CacheVersionDir
{
    mixin CacheDir!();

    bool opCast(T : bool)() const
    {
        return stdExists(_dir);
    }

    @property string ver() const
    {
        return baseName(_dir);
    }

    @property Semver semver() const
    {
        return Semver(ver);
    }

    @property string cacheDir() const
    {
        return packageDir.cacheDir;
    }

    @property CachePackageDir packageDir() const
    {
        return CachePackageDir(dirName(_dir));
    }

    @property string packageName() const
    {
        return baseName(dirName(_dir));
    }

    CacheRevisionDir revisionDir(string rev) const
    {
        const revDir = buildPath(_dir, rev);
        return CacheRevisionDir(revDir);
    }

    auto revisionDirs() const
    {
        import std.algorithm : map;

        return dirInputRange(_dir).map!(rd => CacheRevisionDir(rd));
    }
}

struct CacheRevisionDir
{
    mixin CacheDir!();

    @property string revision() const
    {
        return baseName(_dir);
    }

    @property string cacheDir() const
    {
        return versionDir.cacheDir;
    }

    @property CacheVersionDir versionDir() const
    {
        return CacheVersionDir(dirName(_dir));
    }

    @property CachePackageDir packageDir() const
    {
        return versionDir.packageDir;
    }

    @property RecipeDir recipeDir() const
    {
        return RecipeDir(_dir);
    }

    T opCast(T)() const
    if (is(T == bool) || is(T == RecipeDir))
    {
        static if (is(T == bool))
            return stdExists(_dir);
        else
            return RecipeDir(_dir);
    }

    @property string lockFile() const
    {
        return setExtension(_dir, ".lock");
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
}

private auto dirInputRange(string parent)
{
    import std.algorithm : filter, map;

    return dirEntries(parent, SpanMode.shallow)
        .filter!(e => e.isDir)
        .map!(e => e.name);
}
