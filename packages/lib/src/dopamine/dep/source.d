module dopamine.dep.source;

import dopamine.dep.dub;
import dopamine.api.v1;
import dopamine.cache;
import dopamine.log;
import dopamine.recipe;
import dopamine.recipe.dub;
import dopamine.registry;
import dopamine.semver;

import std.algorithm;
import std.array;
import std.file;
import std.path;
import std.string;

class DependencyException : Exception
{
    import std.exception : basicExceptionCtors;

    mixin basicExceptionCtors;
}

class NoSuchPackageException : DependencyException
{
    string packname;

    this(string packname, string file = __FILE__, size_t line = __LINE__) @safe
    {
        import std.format : format;

        this.packname = packname;
        super(format("No such package: %s", packname), file, line);
    }
}

class NoSuchVersionException : DependencyException
{
    string packname;
    const(Semver) ver;

    this(string packname, const(Semver) ver,
        string file = __FILE__, size_t line = __LINE__) @safe
    {
        import std.format : format;

        this.packname = packname;
        this.ver = ver;
        super(format("No such package version: %s-%s", packname, ver), file, line);
    }
}

class NoSuchRevisionException : DependencyException
{
    string packname;
    const(Semver) ver;
    string revision;

    this(string packname, const(Semver) ver, string revision,
        string file = __FILE__, size_t line = __LINE__) @safe
    {
        import std.format : format;

        this.packname = packname;
        this.ver = ver;
        this.revision = revision;
        super(format("No such package version: %s-%s/%s", packname, ver, revision), file, line);
    }
}


/// Abstraction over a specific source of recipes.
/// e.g. a file system cache, the dopamine registry, the dub registry etc.
interface DepSource
{
    /// versions available for a package
    Semver[] depAvailVersions(string name) @safe;

    /// get the recipe of a package
    RecipeDir depRecipe(string name, Semver ver, string rev = null) @system;
}

final class SystemDepSource : DepSource
{
    Semver[] depAvailVersions(string name) @safe
    {
        import std.process : execute, ProcessException;

        try
        {
            const cmd = ["pkg-config", "--modversion", name];
            const result = execute(cmd);
            if (result.status != 0)
            {
                return [];
            }
            return [Semver(result.output.strip())];
        }
        catch (ProcessException ex)
        {
            logWarningH("Could not execute %s.", info("pkg-config"));
        }
        return [];

    }

    /// get the recipe of a package
    RecipeDir depRecipe(string name, Semver ver, string rev = null)
    {
        assert(false, "System dependencies do not have recipe");
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

    /// get the recipe of a package
    RecipeDir depRecipe(string name, Semver ver, string revision = null)
    {
        if (!revision)
            return findRecipeCache(name, ver);

        const dir = _cache.packageDir(name)
            .versionDir(ver)
            .dopRevisionDir(revision);

        if (!dir)
            return RecipeDir.init;

        auto rdir = RecipeDir.fromDir(dir.dir);
        if (!rdir.recipe)
        {
            logWarningH("Cached package revision %s has no recipe!", info(rdir.root));
            return RecipeDir.init;
        }

        rdir.recipe.revision = revision;

        return rdir;
    }

    private RecipeDir findRecipeCache(string name, const ref Semver ver)
    out (rdir; !rdir.recipe || rdir.recipe.revision.length)
    {
        import std.stdio : File, LockType;

        const vDir = _cache.packageDir(name)
            .versionDir(ver);

        if (!vDir)
            return RecipeDir.init;

        foreach (revDir; vDir.dopRevisionDirs())
        {
            const recFile = checkDopRecipeFile(revDir.dir);
            if (recFile)
            {
                const revLock = revDir.lockFile;
                if (!exists(revLock))
                {
                    logWarning(
                        "%s %s-%s/%s was cached without lock file",
                        warning("Warning:"), name, ver, baseName(revDir.dir)
                    );
                    auto f = File(revLock, "w");
                    f.close();
                }

                auto lock = File(revLock, "r");
                lock.lock(LockType.read);

                auto recipe = parseDopRecipe(recFile, revDir.dir, revDir.revision);
                return RecipeDir(recipe, revDir.dir);
            }
        }

        return RecipeDir.init;
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
        return pack.versions.map!(v => Semver(v)).array;
    }

    RecipeDir depRecipe(string name, Semver ver, string revision = null) @system
    out(rdir; !rdir.recipe || rdir.recipe.revision.length)
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

    /// get the recipe of a package
    RecipeDir depRecipe(string name, Semver ver, string revision = null)
    in (!revision)
    {
        const dir = _cache.packageDir(name)
            .versionDir(ver);

        if (!dir)
            return RecipeDir.init;

        string filename = checkDubRecipeFile(dir.dir);
        if (!filename)
        {
            logWarningH("Cached package revision %s has no recipe!", info(dir.dir));
            return RecipeDir.init;
        }

        auto recipe = parseDubRecipe(filename, dir.dir, ver.toString());
        return RecipeDir(recipe, dir.dir);
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

    RecipeDir depRecipe(string name, Semver ver, string revision = null) @system
    in (!revision)
    {
        auto dir = _cache.downloadAndCachePackage(name, ver);

        string filename = checkDubRecipeFile(dir.dir);
        assert (filename);

        auto recipe = parseDubRecipe(filename, dir.dir, ver.toString());
        return RecipeDir(recipe, dir.dir);
    }
}
