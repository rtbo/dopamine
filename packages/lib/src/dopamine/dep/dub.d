/// Module with utilities to fetch and cache Dub dependencies
module dopamine.dep.dub;

import dopamine.cache;
import dopamine.dep.spec;
import dopamine.log;
import dopamine.recipe;
import dopamine.semver;
import dopamine.util;

import squiz_box;

import std.algorithm;
import std.array;
import std.exception;
import std.file;
import std.format;
import std.json;
import std.net.curl;
import std.path;
import std.string;

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
final class DubRegistry
{
    private struct SubPkgInfo
    {
        string name;
        const(DepSpec)[] deps;
    }

    private struct PkgVersionInfo
    {
        Semver ver;
        const(SubPkgInfo)[] subPkgs;
        const(DepSpec)[] deps;
    }

    private struct PkgInfo
    {
        string name;
        const(PkgVersionInfo)[] versions;
    }

    private string _host;
    private PkgInfo[string] _infoCache;

    this(string host = dubRegistryUrl)
    {
        _host = host;
    }

    Semver[] availPkgVersions(string name) @trusted
    {
        const pn = PackageName(name);

        PkgInfo info = getPkgInfo(pn.pkgName);

        Semver[] res;

        if (pn.isModule)
        {
            res = info.versions
                .filter!(v => v.subPkgs.map!(sp => sp.name).canFind(pn.modName))
                .map!(v => cast(Semver) v.ver)
                .array;
        }
        else
        {
            res = info.versions
                .map!(v => cast(Semver) v.ver)
                .array;
        }

        sort(res);

        return res;
    }

    const(DepSpec)[] pkgDependencies(string name, Semver ver) @trusted
    {
        const pn = PackageName(name);

        PkgInfo info = getPkgInfo(pn.pkgName);

        const(DepSpec)[] deps;

        foreach (pkgv; info.versions)
        {
            if (pkgv.ver != ver)
                continue;

            if (!pn.isModule)
                return pkgv.deps;

            foreach (sp; pkgv.subPkgs)
            {
                if (sp.name == pn.modName)
                    return sp.deps;
            }
        }

        throw new DubRegistryNotFoundException(
            format!"DUB package version %s/%s could not be found"(name, ver));
    }

    private const(DepSpec)[] depsFromJson(string name, Semver ver, JSONValue[string] deps) const @safe
    {
        const(DepSpec)[] res;
        foreach (k, v; deps)
        {
            const pn = PackageName(k);
            VersionSpec spec;
            if (pn.isModule && pn.pkgName == name)
            {
                spec = VersionSpec("==" ~ ver.toString());
            }
            else
            {
                string str;
                if (v.type == JSONType.string)
                    str = v.str;
                else
                    str = v["version"].str;
                if (str.indexOf('.') == -1)
                    str ~= ".0";
                try
                    spec = VersionSpec(str);
                catch (Exception ex)
                    throw new IgnoreDubPkgVersion();
            }
            res ~= DepSpec(k, spec, DepProvider.dub);
        }
        return res;
    }

    private const(SubPkgInfo)[] subPkgsFromJson(string name, Semver ver, JSONValue[] jspkgs)
    {
        const(SubPkgInfo)[] spkgs;
        foreach (jspkg; jspkgs)
        {
            const(DepSpec)[] deps;
            if (auto jdeps = "dependencies" in jspkg)
                deps = depsFromJson(name, ver, jdeps.objectNoRef);
            spkgs ~= SubPkgInfo(jspkg["name"].str, deps);
        }
        return spkgs;
    }

    private PkgInfo getPkgInfo(string name) @trusted
    {
        if (auto p = name in _infoCache)
            return *p;

        const url = format!"%s/api/packages/%s/info?minimize=true"(_host, name);

        logVerbose("fetching DUB package info for %s at %s", info(name), url);

        try
        {
            auto json = parseJSON(std.net.curl.get(url));

            const(PkgVersionInfo)[] vers;
            auto jvers = "versions" in json;
            if (!jvers)
                throw new DubRegistryNotFoundException(format!"Expected key 'versions' at %s"(url));

            foreach (jver; jvers.arrayNoRef)
            {
                const sver = jver["version"].str;
                if (!Semver.isValid(sver))
                    continue;

                const ver = Semver(sver);

                const(SubPkgInfo)[] spkgs;
                const(DepSpec)[] deps;

                try
                {
                    auto jspkgs = "subPackages" in jver;
                    if (jspkgs)
                        spkgs = subPkgsFromJson(name, ver, jspkgs.arrayNoRef);

                    auto jdeps = "dependencies" in jver;
                    if (jdeps)
                        deps = depsFromJson(name, ver, jdeps.objectNoRef);
                }
                catch (IgnoreDubPkgVersion)
                    continue;

                vers ~= PkgVersionInfo(ver, spkgs, deps);
            }

            auto pkg = PkgInfo(name, vers);
            _infoCache[name] = pkg;
            return pkg;
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

        logInfo("Downloading %s", url);

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

private class IgnoreDubPkgVersion : Exception
{
    this()
    {
        super("");
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
        import std.typecons : Yes;

        const dir = CachePackageDir(buildPath(_dir, name)).versionDir(ver.toString());

        mkdirRecurse(dirName(dir.dir));

        auto lock = File(dir.dubLockFile, "w");
        lock.lock();

        enforce(
            !exists(dir.dir),
            format!"Dub package %s-%s already in cache at %s"(name, ver, dir.dir)
        );

        mkdir(dir.dir);

        readBinaryFile(zipFile)
            .unboxZip(Yes.removePrefix)
            .each!(e => e.extractTo(dir.dir));

        return dir;
    }
}

@("DubPackageCache")
@system
unittest
{
    import std.array;

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
    assertThrown!DubRegistryNotFoundException(reg.downloadPkgZipToFile("not-a-package", Semver(
            "1.0.0")));
}
