module dopamine.cache;

import dopamine.api.v1;
import dopamine.log;
import dopamine.registry;
import dopamine.paths;

import dopamine.cache_dirs;

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

    CacheRevisionDir cacheRecipe(Registry registry,
        const ref PackageResource pack,
        string ver,
        string revision = null)
    out (res; res.exists)
    {
        import std.algorithm : canFind, map;
        import std.conv : to;
        import std.format : format;
        import std.stdio : File;

        if (revision)
        {
            const revDir = packageDir(pack.name).versionDir(ver).revisionDir(revision);
            if (revDir && RecipeDir(revDir.dir).hasRecipeFile)
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

        enforce(resp.payload.ver == ver, new Exception(
                "Registry returned a package version that do not match request:\n" ~
                format("  - requested %s/%s\n", pack.name, ver) ~
                format("  - obtained %s/%s", pack.name, resp.payload.ver)
        ));

        if (revision)
            enforce(resp.payload.revision == revision, new Exception(
                    "Registry returned a revision that do not match request"
            ));
        else
            revision = resp.payload.revision;

        auto revDir = packageDir(pack.name)
            .versionDir(resp.payload.ver)
            .revisionDir(resp.payload.revision);

        mkdirRecurse(revDir.versionDir.dir);

        auto lock = File(revDir.lockFile, "w");
        lock.lock();

        mkdirRecurse(revDir.dir);
        auto recDir = RecipeDir(revDir.dir);

        debug { import std.stdio : writefln; try { writefln!"FIXME recipe download %s:%s"(__FILE__, __LINE__); } catch (Exception) {} }
        // if (resp.payload.fileList.length == 1)
        // {
            write(recDir.recipeFile, resp.payload.recipe);
        // }
        // else
        // {
        //     assert(false, "unimplemented");
        // }

        return revDir;
    }
}
