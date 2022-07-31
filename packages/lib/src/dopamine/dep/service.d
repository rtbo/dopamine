module dopamine.dep.service;

import dopamine.dep.dub;
import dopamine.dep.source;
import dopamine.api.v1;
import dopamine.cache;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.registry;
import dopamine.semver;

import std.exception;
import std.string;
import std.typecons;

/// enum that describe the location of a dependency
enum DepLocation : uint
{
    system = 0,
    cache = 1,
    network = 2,
}

/// An available version of a package
/// and indication of its location
struct AvailVersion
{
    Semver ver;
    DepLocation location;

    int opCmp(ref const AvailVersion rhs) const
    {
        if (ver < rhs.ver)
        {
            return -1;
        }
        if (ver > rhs.ver)
        {
            return 1;
        }
        if (cast(int) location < cast(int) rhs.location)
        {
            return -1;
        }
        if (cast(int) location > cast(int) rhs.location)
        {
            return 1;
        }
        return 0;
    }
}

/// Abstract interface to a dependency service.
/// The service looks for available dependencies in the user system,
/// the local cache of recipes and the remote registry.
/// The service also caches new recipe locally and keep them in memory
/// for fast access.
///
/// This is a final class, but abstraction is provided by the DepSource
/// interfaces. Dependency resolution (such as in dopamine.dep.dag) will
/// typically use one DepService for regular dependencies and one
/// for dub dependencies.
final class DepService
{
    private DepSource[3] _sources;

    /// in memory cache
    private RecipeDir[string] _recipeMem;

    /// Build a DepService that will operate over the 3 provided
    /// sources, one for each of the `DepLocation` fields.
    /// Each can be null, but at least one must be non-null.
    this(DepSource system, DepSource cache, DepSource network)
    {
        assert(system || cache || network);
        _sources[DepLocation.system] = system;
        _sources[DepLocation.cache] = cache;
        _sources[DepLocation.network] = network;
    }

    /// Get the available versions of a package.
    /// If a version is available in several locations, multiple
    /// entries are returned.
    ///
    /// Params:
    ///     packname = name of the package
    ///
    /// Returns: the list of versions available of the package
    ///
    /// Throws: NoSystemDependencies, ServerDownException, NoSuchPackageException
    AvailVersion[] packAvailVersions(string name) @safe
    {
        import std.algorithm : map, sort;
        import std.array;

        AvailVersion[] vers;

        foreach (i, s; _sources)
        {
            const loc = cast(DepLocation) i;
            if (s)
            {
                vers ~= s.depAvailVersions(name).map!(v => AvailVersion(v, loc)).array;
            }
        }

        enforce(vers.length, new NoSuchPackageException(name));

        (() @trusted => sort(vers))();

        return vers;
    }

    /// Get the recipe of a package in the specified version (and optional revision)
    /// Throws: ServerDownException, NoSuchPackageException, NoSuchVersionException, NoSuchRevisionException
    ///         or any exception thrown during recipe parsing
    RecipeDir packRecipe(string name, const(AvailVersion) aver, string revision = null) @system
    in (aver.location != DepLocation.system, "System dependencies have no recipe!")
    in (_sources[aver.location], "No source for requested location")
    out (rdir; rdir.recipe.isDub || rdir.recipe.revision.length)
    {
        if (revision)
        {
            auto rdir = packRecipeMem(name, aver.ver, revision);
            if (rdir.recipe)
            {
                return rdir;
            }
        }

        RecipeDir rdir;

        bool inCache = _sources[DepLocation.cache].hasPackage(name, aver.ver, revision);

        if (aver.location == DepLocation.network && inCache)
            rdir = _sources[DepLocation.cache].depRecipe(name, aver.ver, revision);
        else if (!inCache && _sources[DepLocation.network])
            rdir = _sources[DepLocation.network].depRecipe(name, aver.ver, revision);
        else
            rdir = _sources[aver.location].depRecipe(name, aver.ver, revision);

        memRecipe(rdir);
        return rdir;
    }

    private void memRecipe(RecipeDir rdir)
    {
        auto recipe = rdir.recipe;
        const id = depId(recipe.name, recipe.ver, recipe.revision);
        _recipeMem[id] = rdir;
    }

    private RecipeDir packRecipeMem(string name, const ref Semver ver, string revision)
    out (rdir; !rdir.recipe || rdir.recipe.revision.length)
    {
        const id = depId(name, ver, revision);

        if (auto p = id in _recipeMem)
            return *p;

        return RecipeDir.init;
    }

    private string depId(string packname, Semver ver, string revision) @safe
    {
        pragma(inline, true);

        import std.format : format;

        return format("%s/%s/%s", packname, ver, revision);
    }

    private noreturn verOrRevException(string packname, const ref Semver ver, string revision)
    {
        throw revision ?
            new NoSuchRevisionException(packname, ver, revision) : new NoSuchVersionException(packname, ver);
    }
}

DepService buildDepService(Flag!"system" enableSystem,
    PackageCache dopCache,
    Registry registry)
in (dopCache, "Cache is mandatory")
{
    DepSource system;
    DepSource cache;
    DepSource network;

    if (enableSystem)
        system = new SystemDepSource();

    cache = new DopCacheDepSource(dopCache);

    if (registry)
    {
        network = new DopRegistryDepSource(registry, dopCache);
    }

    return new DepService(system, cache, network);
}

DepService buildDepService(Flag!"system" enableSystem,
    string cacheDir = homeCacheDir(),
    string registryUrl = dopamine.registry.registryUrl())
in (cacheDir, "Cache directory is mandatory")
{
    auto cache = new PackageCache(cacheDir);
    Registry registry;
    if (registryUrl)
        registry = new Registry(registryUrl);
    return buildDepService(enableSystem, cache, registry);
}

DepService buildDubDepService(DubPackageCache dubCache, DubRegistry registry)
in (dubCache, "Cache is mandatory")
{
    DepSource cache;
    DepSource network;

    cache = new DubCacheDepSource(dubCache);

    if (registry)
    {
        network = new DubRegistryDepSource(registry, dubCache);
    }

    return new DepService(null, cache, network);
}

DepService buildDubDepService(string cacheDir = homeDubCacheDir(), string registryUrl = dubRegistryUrl)
in (cacheDir, "Cache directory is mandatory")
{
    auto cache = new DubPackageCache(cacheDir);
    DubRegistry registry;
    if (registryUrl)
        registry = new DubRegistry(registryUrl);
    return buildDubDepService(cache, registry);
}

struct DepServices
{
    DepService dop;
    DepService dub;
}
