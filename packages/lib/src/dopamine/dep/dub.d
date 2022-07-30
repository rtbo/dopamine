module dopamine.dep.dub;

import dopamine.cache_dirs;
import dopamine.log;
import dopamine.recipe;
import dopamine.semver;
import dopamine.util;

import squiz_box;

import std.algorithm;
import std.exception;
import std.file;
import std.format;
import std.json;
import std.net.curl;
import std.path;

@safe:

/// Access to the Dub registry
class DubRegistry
{
    private string _host;

    this(string host = "https://code.dlang.org")
    {
        _host = host;
    }

    Semver[] availPkgVersions(string name) const @trusted
    {
        const url = format!"%s/api/packages/%s/info?minimize=true"(_host, name);
        auto json = parseJSON(std.net.curl.get(url));
        auto vers = "versions" in json;
        if (!vers)
            return [];
        Semver[] res;
        foreach (jver; vers.array)
        {
            const ver = jver["version"].str;
            if (Semver.isValid(ver))
                res ~= Semver(ver);
        }
        sort(res);
        return res;
    }

    // FIXME: returns a range on bytes. Need the "multi" API of libcurl, not available with D.
    string downloadPkgToFile(string name, Semver ver, string filename = null) const
    {
        if (!filename)
            filename = tempPath(null, format!"%s-%s"(name, ver), ".zip");

        const url = format!"%s/packages/%s/%s.zip"(_host, name, ver);

        (() @trusted => download(url, filename))();

        return filename;
    }

    unittest
    {
        auto reg = new DubRegistry();
        auto vers = reg.availPkgVersions("squiz-box");
        assert(vers.canFind(Semver("0.1.0")));
        assert(vers.canFind(Semver("0.2.0")));
        assert(vers.canFind(Semver("0.2.1")));
    }
}

/// A local package cache for dub packages.
/// Warning: Dopamine do not use the same directory structure as Dub, so
/// the genuine Dub package cache (~/.dub/packages) cannot be used here.
class DubPackageCache
{
    private string _dir;
    private DubRegistry _registry;

    /// Construct a cache in the specified directory.
    /// [dir] would typically be "~/.dop/dub-cache" on Linux and "%LOCALAPPDATA%\dop\dub-cache" on Windows.
    this(string dir, DubRegistry registry)
    {
        _dir = dir;
        _registry = registry;
    }

    /// Get an InputRange of CachePackageDir of all packages in the cache.
    /// Throws: FileException if the cache directory does not exist
    auto packageDirs() const @trusted
    {
        import std.algorithm : map;

        return dirInputRange(_dir)
            .map!(d => CachePackageDir(d));
    }

    /// Get a CachePackageDir for the package [name]
    CachePackageDir packageDir(string name) const
    {
        return CachePackageDir(buildPath(_dir, name));
    }

    CacheVersionDir downloadAndCachePackage(string name, Semver ver) const @trusted
    {
        import std.stdio : File;

        const dir = CachePackageDir(buildPath(_dir, name)).versionDir(ver.toString());

        mkdirRecurse(dirName(dir.dir));

        auto lock = File(dir.dubLockFile, "w");
        lock.lock();

        enforce(
            !exists(dir.dir),
            format!"Dub package %s-%s already in cache at %s"(name, ver, dir.dir)
        );

        mkdir(dir.dir);
        string zipFile = _registry.downloadPkgToFile(name, ver);

        const removePrefix = format!"%s-%s/"(name, ver);

        readBinaryFile(zipFile)
            .unboxZip()
            .each!(e => e.extractTo(dir.dir, removePrefix));

        return dir;
    }
}

@("DubPackageCache")
@trusted
unittest
{
    import std.array;
    import std.stdio;

    auto dir = tempPath(null, "dub-cache");

    writeln(dir);

    mkdirRecurse(dir);
    scope (success)
        rmdirRecurse(dir);

    auto reg = new DubRegistry();
    auto cache = new DubPackageCache(dir, reg);

    auto packDir = cache.packageDir("squiz-box");
    assert(!packDir.exists);

    auto verDir = cache.downloadAndCachePackage("squiz-box", Semver("0.2.1"));

    assert(packDir.versionDirs().array.length == 1);
    assert(verDir.dir == buildPath(dir, "squiz-box", "0.2.1"));
    assert(isFile(verDir.path("meson.build")));
    assert(isFile(verDir.path("dub.json")));
}
