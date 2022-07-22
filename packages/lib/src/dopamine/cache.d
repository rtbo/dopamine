module dopamine.cache;

import dopamine.api.v1;
import dopamine.cache_dirs;
import dopamine.log;
import dopamine.registry;
import dopamine.paths;
import dopamine.util;

import squiz_box;

import std.array;
import std.digest.sha;
import std.exception;
import std.file;
import std.path;
import std.range;

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
        import std.algorithm : canFind, each, map;
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

        auto dig = makeDigest!SHA256();
        auto downloadReq = DownloadRecipeArchive(recipeRes.id);
        DownloadMetadata archiveMetadata;
        auto archiveData = registry.download(downloadReq, archiveMetadata)
            .tee(&dig)
            .join();

        // keep filename creation lazy
        const filenameFun = (() => archiveMetadata.filename ?
                archiveMetadata.filename
                : format!"%s-%s-%s.tar.xz"(pack.name, ver, revision));

        if (archiveMetadata.sha256.length)
        {
            enforce(
                dig.finish() == archiveMetadata.sha256,
                "Could not verify integrity of " ~ filenameFun(),
            );
        }
        else
        {
            logWarningH(
                "Cannot verify integrity of %s: No digest received from registry",
                info(filenameFun())
            );
        }

        // now that archive is verified, proceed filesystem modifications and decompression

        auto revDir = packageDir(pack.name)
            .versionDir(recipeRes.ver)
            .revisionDir(recipeRes.revision);

        mkdirRecurse(revDir.versionDir.dir);

        auto lock = File(revDir.lockFile, "w");
        lock.lock();

        mkdirRecurse(revDir.dir);

        only(archiveData)
            .decompressXz()
            .unboxTar()
            .each!(e => e.extractTo(revDir.dir));

        RecipeDir.enforced(revDir.dir);

        return revDir;
    }
}
