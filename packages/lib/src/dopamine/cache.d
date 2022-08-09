module dopamine.cache;

import dopamine.api.v1;
import dopamine.log;
import dopamine.recipe;
import dopamine.registry;
import dopamine.util;

import squiz_box;

import std.array;
import std.digest.sha;
import std.exception;
import std.file;
import std.path;
import std.range;

public import dopamine.cache_dirs;

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
    auto packageDirs() const
    {
        import std.algorithm : map;

        return dirInputRange(_dir)
            .map!(d => CachePackageDir(d));
    }

    /// Get a CachePackageDir for the package [packname]
    CachePackageDir packageDir(string packname) const @safe
    {
        return CachePackageDir(buildPath(_dir, packname));
    }

    CacheRevisionDir cacheRecipe(Registry registry,
        const ref PackageResource pack,
        string ver,
        string revision = null)
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
            logInfo("Fetching recipe %s/%s from registry", info(pack.name), info(ver));
        }

        Response!RecipeResource resp;
        if (revision)
            resp = registry.sendRequest(GetRecipeRevision(pack.name, ver, revision));
        else
            resp = registry.sendRequest(GetLatestRecipeRevision(pack.name, ver));

        enforce(resp.code < 400, new ErrorLogException(
                "Could not fetch %s/%s%s%s: registry returned %s",
                info(pack.name), info(ver), revision ? "/" : "", info(revision ? revision : ""),
                error(resp.code.to!string)
        ));

        const recipeRes = resp.payload;

        enforce(recipeRes.ver == ver, new Exception(
                "Registry returned a package version that do not match request:\n" ~
                format("  - requested %s/%s\n", pack.name, ver) ~
                format("  - obtained %s/%s", pack.name, recipeRes.ver)
        ));

        if (revision)
            enforce(recipeRes.revision == revision, new Exception(
                    "Registry returned a revision that do not match request"
            ));
        else
            revision = recipeRes.revision;

        const archiveName = recipeRes.archiveName;
        const filename = buildPath(tempDir(), archiveName);
        registry.downloadArchive(archiveName, filename);

        scope(exit)
            remove(filename);

        auto revDir = packageDir(pack.name)
            .versionDir(recipeRes.ver)
            .dopRevisionDir(recipeRes.revision);

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
