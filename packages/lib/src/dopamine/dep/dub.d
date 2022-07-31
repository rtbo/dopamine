/// Module with utilities to fetch and cache Dub dependencies
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

class DubRegistryNotFoundException : Exception
{
    mixin basicExceptionCtors!();
}

class DubRegistryErrorException : Exception
{
    mixin basicExceptionCtors!();
}

const dubRegistryUrl = "https://code.dlang.org";

/// Access to the Dub registry
class DubRegistry
{
    private string _host;

    this(string host = dubRegistryUrl)
    {
        _host = host;
    }

    Semver[] availPkgVersions(string name) const @trusted
    {
        const url = format!"%s/api/packages/%s/info?minimize=true"(_host, name);

        try
        {
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
        catch (HTTPStatusException ex)
        {
            if (ex.status == 404)
                throw new DubRegistryNotFoundException(format!"%s returned 404"(url));
            throw new DubRegistryErrorException(format!"%s returned %s"(url, ex.status));
        }
    }

    // FIXME: returns a range on bytes. Need the "multi" API of libcurl, not available with D.
    string downloadPkgZipToFile(string name, Semver ver, string filename = null) const @trusted
    {
        import std.stdio : File;

        const url = format!"%s/packages/%s/%s.zip"(_host, name, ver);

        if (!filename)
            filename = tempPath(null, format!"%s-%s"(name, ver), ".zip");

        auto f = File(filename, "wb");
        auto http = HTTP();
        http.url = url;
        http.onReceive = (ubyte[] data) { f.rawWrite(data); return data.length; };
        HTTP.StatusLine statusLine;
        http.onReceiveStatusLine((HTTP.StatusLine line) { statusLine = line; });

        http.perform();

        enforce(
            statusLine.code != 404,
            new DubRegistryNotFoundException(format!"%s returned 404"(url))
        );
        enforce(
            statusLine.code < 400,
            new DubRegistryErrorException(format!"%s returned %s"(url, statusLine.code))
        );

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

    unittest
    {
        auto reg = new DubRegistry();
        assertThrown!DubRegistryNotFoundException(reg.availPkgVersions("not-a-package"));
    }
}

/// A local package cache for dub packages.
/// Warning: Dopamine do not use the same directory structure as Dub, so
/// the genuine Dub package cache (~/.dub/packages) cannot be used here.
class DubPackageCache
{
    private string _dir;

    /// Construct a cache in the specified directory.
    /// [dir] would typically be "~/.dop/dub-cache" on Linux and "%LOCALAPPDATA%\dop\dub-cache" on Windows.
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

    /// Get a CachePackageDir for the package [name]
    CachePackageDir packageDir(string name) const
    {
        return CachePackageDir(buildPath(_dir, name));
    }

    CacheVersionDir cachePackageZip(string name, Semver ver, string zipFile) const @trusted
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

        const removePrefix = format!"%s-%s/"(name, ver);

        readBinaryFile(zipFile)
            .unboxZip()
            .each!(e => e.extractTo(dir.dir, removePrefix));

        return dir;
    }
}

@("DubPackageCache")
@system
unittest
{
    import std.array;
    import std.stdio;

    auto dir = tempPath(null, "dub-cache");

    mkdirRecurse(dir);
    scope (success)
        rmdirRecurse(dir);

    auto reg = new DubRegistry();
    auto cache = new DubPackageCache(dir);

    auto packDir = cache.packageDir("squiz-box");
    assert(!packDir.exists);

    const name = "squiz-box";
    const ver = Semver("0.2.1");
    const zip = reg.downloadPkgZipToFile(name, ver);
    auto verDir = cache.cachePackageZip(name, ver, zip);

    assert(packDir.versionDirs().array.length == 1);
    assert(verDir.dir == buildPath(dir, "squiz-box", "0.2.1"));
    assert(isFile(verDir.path("meson.build")));
    assert(isFile(verDir.path("dub.json")));
}

@("DubRegistry 404")
@system
unittest
{
    auto reg = new DubRegistry();
    assertThrown!DubRegistryNotFoundException(reg.downloadPkgZipToFile("not-a-package", Semver("1.0.0")));
}
