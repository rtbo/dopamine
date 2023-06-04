module dopamine.dep.source;

import dopamine.dep.dub;
import dopamine.api.v1;
import dopamine.cache;
import dopamine.log;
import dopamine.profile;
import dopamine.recipe;
import dopamine.recipe.dub;
import dopamine.registry;
import dopamine.semver;

import std.algorithm;
import std.array;
import std.exception;
import std.file;
import std.path;
import std.string;

/// Exception thrown when a dependency can't be found
class DependencyException : Exception
{
    string name;

    this(string name, string msg, Throwable next = null, string file = __FILE__, size_t line = __LINE__) @safe
    {
        this.name = name;
        super(msg, next, file, line);
    }
}

/// Problem with look-up of system dependencies
/// Likely pkg-config is not available
class NoSystemDependencies : DependencyException
{
    this(string name, string msg, Throwable next = null, string file = __FILE__, size_t line = __LINE__) @safe
    {
        super(name, msg, next, file, line);
    }
}

/// A package could not be found
class NoSuchPackageException : DependencyException
{
    this(string name, string file = __FILE__, size_t line = __LINE__) @safe
    {
        import std.format : format;

        super(name, format("No such package: %s", name), null, file, line);
    }
}


/// A package module could not be found
class NoSuchPackageModuleException : DependencyException
{
    this(string pkg, string mod, string file = __FILE__, size_t line = __LINE__) @safe
    {
        import std.format : format;

        super(name, format("No such package module: %s:%s", pkg, mod), null, file, line);
    }
}

/// A package version could not be found
class NoSuchVersionException : DependencyException
{
    const(Semver) ver;

    this(string name, const(Semver) ver,
        string file = __FILE__, size_t line = __LINE__) @safe
    {
        import std.format : format;

        this.ver = ver;
        super(name, format("No such package version: %s-%s", name, ver), null, file, line);
    }
}

/// A package revision could not be found
class NoSuchRevisionException : DependencyException
{
    const(Semver) ver;
    string revision;

    this(string name, const(Semver) ver, string revision,
        string file = __FILE__, size_t line = __LINE__) @safe
    {
        import std.format : format;

        this.ver = ver;
        this.revision = revision;
        super(name, format("No such package version: %s/%s/%s", name, ver, revision), null, file, line);
    }
}

/// Abstraction over a specific source of recipes.
/// e.g. a file system cache, the dopamine registry, the dub registry etc.
interface DepSource
{
    /// Versions available for a package
    /// Returns: the versions available, or [] if none was found
    /// Throws: NoSystemDependencies
    Semver[] depAvailVersions(string name) @safe
    in (!PackageName(name).isModule);


    /// Check if package is present in specified version/revision
    bool hasPackage(string name, Semver ver, string revision = null) @safe
    in (!PackageName(name).isModule);

    /// Get the recipe of a package
    /// Returns: The RecipeDir with parsed recipe
    /// Throws: NoSuchPackageException, NoSuchVersionException, NoSuchRevisionException
    RecipeDir depRecipe(string name, Semver ver, string rev = null) @system
    in (!PackageName(name).isModule)
    out (rdir; rdir.recipe !is null);

    /// Whether this source can provide dependencies
    @property bool hasDepDependencies();

    /// Get the dependencies of a package
    const(DepSpec)[] depDependencies(const(Profile) profile, string name, Semver ver, string rev = null);
}

final class SystemDepSource : DepSource
{
    Semver[] depAvailVersions(string name) @safe
    {
        import dopamine.util : pkgConfigExe;
        import std.process : execute, ProcessException;

        try
        {
            const cmd = [pkgConfigExe, "--modversion", name];
            const result = execute(cmd);
            if (result.status != 0)
            {
                return [];
            }
            return [Semver(result.output.strip())];
        }
        catch (ProcessException ex)
        {
            throw new NoSystemDependencies(name, "Could not execute pkg-config", ex);
        }
    }

    bool hasPackage(string name, Semver ver, string revision) @safe
    {
        import dopamine.util : pkgConfigExe;
        import std.process : execute, ProcessException;

        assert(!revision, "System dependencies do not have revision");

        try
        {
            const cmd = [pkgConfigExe, "--modversion", name];
            const result = execute(cmd);
            return result.status == 0 && result.output.strip() == ver;
        }
        catch (ProcessException ex)
        {
            return false;
        }
    }

    /// get the recipe of a package
    RecipeDir depRecipe(string name, Semver ver, string rev = null)
    {
        assert(false, "System dependencies do not have recipe");
    }

    @property bool hasDepDependencies()
    {
        // TODO: pkg-config dependencies
        return false;
    }

    const(DepSpec)[] depDependencies(const(Profile) profile, string name, Semver ver, string rev = null)
    {
        // TODO: pkg-config dependencies
        assert(false, "Not implemented");
    }
}

final class DopCacheDepSource : DepSource
{
    private PackageCache _cache;

    this(PackageCache cache)
    {
        _cache = cache;
    }

    Semver[] depAvailVersions(string name) @trusted
    {
        auto pdir = _cache.packageDir(name);
        if (!pdir)
            return [];

        auto vers = pdir.versionDirs()
            .map!(vd => vd.semver)
            .array;
        vers.sort!((a, b) => a > b);
        return vers;
    }

    bool hasPackage(string name, Semver ver, string revision) @safe
    {
        const vDir = _cache.packageDir(name).versionDir(ver);
        if (!vDir.exists)
            return false;

        if (!revision)
            revision = findRecipeRevision(name, ver);

        const revDir = vDir.dopRevisionDir(revision);
        return checkDopRecipeFile(revDir.dir).length > 0;
    }

    /// get the recipe of a package
    RecipeDir depRecipe(string name, Semver ver, string revision = null)
    {
        import std.stdio : File, LockType;

        const pDir = _cache.packageDir(name);
        enforce(pDir.exists, new NoSuchPackageException(name));

        const vDir = pDir.versionDir(ver);
        enforce(vDir.exists, new NoSuchVersionException(name, ver));

        if (!revision)
            revision = findRecipeRevision(name, ver);

        enforce(revision, new NoSuchVersionException(name, ver));

        const revDir = vDir.dopRevisionDir(revision);
        const recFile = checkDopRecipeFile(revDir.dir);
        enforce(recFile, new NoSuchRevisionException(name, ver, revision));

        const revLock = revDir.lockFile;
        if (!exists(revLock))
        {
            logWarningH(
                "%s/%s/%s was cached without lock file",
                name, ver, revision
            );
            auto f = File(revLock, "w");
            f.close();
        }

        auto lock = File(revLock, "r");
        lock.lock(LockType.read);

        auto recipe = parseDopRecipe(recFile, revDir.dir, revDir.revision);
        return RecipeDir(recipe, revDir.dir);
    }

    private string findRecipeRevision(string name, Semver ver) @trusted
    {
        const vDir = _cache.packageDir(name).versionDir(ver);
        assert(vDir.exists);

        foreach (revDir; vDir.dopRevisionDirs())
        {
            const recFile = checkDopRecipeFile(revDir.dir);
            if (recFile)
                return revDir.revision;
        }

        return null;
    }

    @property bool hasDepDependencies()
    {
        return false;
    }

    const(DepSpec)[] depDependencies(const(Profile) profile, string name, Semver ver, string rev = null)
    {
        assert(false, "Not implemented");
    }
}

final class DopRegistryDepSource : DepSource
{
    private Registry _registry;
    private PackageCache _cache;
    private PackageResource[string] _packMem;

    this(Registry registry, PackageCache cache)
    {
        _registry = registry;
        _cache = cache;
    }

    Semver[] depAvailVersions(string name) @safe
    {
        auto pack = packagePayload(name);
        return pack.versions.map!(v => Semver(v.ver)).array;
    }

    bool hasPackage(string name, Semver ver, string revision) @safe
    {
        auto pack = packagePayload(name);
        auto packVer = pack.versions.find!(v => v.ver == ver.toString());
        if (!packVer.length)
            return false;

        if (revision)
            return (packVer[0].recipes.find!(r => r.revision == revision)).length != 0;
        else
            return true;
    }

    RecipeDir depRecipe(string name, Semver ver, string revision = null) @system
    out (rdir; !rdir.recipe || rdir.recipe.revision.length)
    {
        auto pack = packagePayload(name);
        auto revDir = _cache.cacheRecipe(_registry, pack, ver.toString(), revision);

        auto rdir = RecipeDir.fromDir(revDir.dir);
        assert(rdir.recipe);
        rdir.recipe.revision = revDir.revision;
        return rdir;
    }

    private PackageResource packagePayload(string name) @trusted
    in (_registry)
    {
        import std.exception : enforce;

        if (auto p = name in _packMem)
            return *p;

        auto req = GetPackage(name);
        auto resp = _registry.sendRequest(req);
        enforce(resp.code != 404, new NoSuchPackageException(name));
        auto pack = resp.payload;
        _packMem[name] = pack;
        return pack;
    }

    @property bool hasDepDependencies()
    {
        return false;
    }

    const(DepSpec)[] depDependencies(const(Profile) profile, string name, Semver ver, string rev = null)
    {
        assert(false, "Not implemented");
    }
}

final class DubCacheDepSource : DepSource
{
    private DubPackageCache _cache;

    this(DubPackageCache cache)
    {
        _cache = cache;
    }

    Semver[] depAvailVersions(string name) @trusted
    {
        auto pdir = _cache.packageDir(name);
        if (!pdir)
            return [];

        auto vers = pdir.versionDirs()
            .map!(vd => vd.semver)
            .array;

        vers.sort!((a, b) => a > b);
        return vers;
    }

    bool hasPackage(string name, Semver ver, string revision) @safe
    {
        assert(!revision, "Dub recipes have no revision");

        const vDir = _cache.packageDir(name).versionDir(ver);
        return checkDubRecipeFile(vDir.dir).length > 0;
    }

    /// get the recipe of a package
    RecipeDir depRecipe(string name, Semver ver, string revision = null)
    {
        assert(!revision, "Dub recipes have no revision");

        const pDir = _cache.packageDir(name);
        enforce(pDir.exists, new NoSuchPackageException(name));

        const vDir = pDir.versionDir(ver);
        enforce(vDir.exists, new NoSuchVersionException(name, ver));

        string filename = checkDubRecipeFile(vDir.dir);
        enforce(filename, new NoSuchVersionException(name, ver));

        auto recipe = parseDubRecipe(filename, vDir.dir, ver.toString());
        return RecipeDir(recipe, vDir.dir, relativePath(filename, vDir.dir));
    }

    @property bool hasDepDependencies()
    {
        return false;
    }

    const(DepSpec)[] depDependencies(const(Profile) profile, string name, Semver ver, string rev = null)
    {
        assert(false, "Not implemented");
    }
}

final class DubRegistryDepSource : DepSource
{
    private DubRegistry _registry;
    private DubPackageCache _cache;

    this(DubRegistry registry, DubPackageCache cache)
    {
        _registry = registry;
        _cache = cache;
    }

    Semver[] depAvailVersions(string name) @safe
    {
        return _registry.availPkgVersions(name);
    }

    bool hasPackage(string name, Semver ver, string revision) @safe
    {
        assert(!revision, "Dub recipes have no revision");

        return depAvailVersions(name).canFind(ver);
    }

    RecipeDir depRecipe(string name, Semver ver, string revision = null) @system
    in (!PackageName(name).isModule)
    {
        assert(!revision, "Dub recipes have no revision");

        try
        {
            const zipFile = _registry.downloadPkgZipToFile(name, ver);
            scope (exit)
                remove(zipFile);

            auto dir = _cache.cachePackageZip(name, ver, zipFile);

            string filename = checkDubRecipeFile(dir.dir);
            assert(filename);

            auto recipe = parseDubRecipe(filename, dir.dir, ver.toString());
            return RecipeDir(recipe, dir.dir, relativePath(filename, dir.dir));
        }
        catch (DubRegistryNotFoundException ex)
        {
            throw new NoSuchVersionException(name, ver);
        }
    }

    @property bool hasDepDependencies()
    {
        return true;
    }

    const(DepSpec)[] depDependencies(const(Profile) profile, string name, Semver ver, string rev = null)
    {
        return _registry.pkgDependencies(name, ver);
    }
}
