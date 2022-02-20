module dopamine.dep.service;

import dopamine.api;
import dopamine.dep.resolved;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.typecons;

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

/// enum that describe the location of a dependency
enum DepLocation
{
    system,
    cache,
    network,
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
interface DepService
{
    /// Get the available versions of a package.
    /// If a version is available in several locations, multiple
    /// entries are returned.
    ///
    /// Params:
    ///     packname = name of the package
    ///
    /// Returns: the list of versions available of the package
    ///
    /// Throws: ServerDownException, NoSuchPackageException
    AvailVersion[] packAvailVersions(string packname) @safe;

    /// Get the recipe of a package in the specified version (and optional revision)
    Recipe packRecipe(string packname, const(AvailVersion) aver, string rev = null) @system
    in (aver.location != DepLocation.system, "System dependencies have no recipe!");
}

/// Actual implementation of [DepService]
final class DependencyService : DepService
{
    private PackagePayload[string] _packMem;
    private Recipe[string] _recipeMem;

    private Flag!"network" _network;
    private Flag!"system" _system;

    private alias RecipeAndId = Tuple!(Recipe, string);

    this(Flag!"network" network, Flag!"system" system)
    {
        _network = network;
        _system = system;
    }

    AvailVersion[] packAvailVersions(string packname) @trusted
    {
        import std.algorithm : sort;

        AvailVersion[] vers = packAvailVersionsCache(packname);

        if (_system)
            vers ~= packAvailVersionsSystem(packname);

        if (_network)
            vers ~= packAvailVersionsNetwork(packname);

        sort(vers);
        return vers;
    }

    private AvailVersion[] packAvailVersionsSystem(string packname) @safe
    {
        import std.process : execute, ProcessException;

        try
        {
            const cmd = ["pkg-config", "--modversion", packname];
            const result = execute(cmd);
            if (result.status != 0)
            {
                return [];
            }
            return [AvailVersion(Semver(result.output), DepLocation.system)];
        }
        catch (ProcessException ex)
        {
            logWarningH(
                "Could not execute %s. Skipping discovery of system dependencies.",
                info("pkg-config")
            );
            _system = No.system;
        }
        return [];
    }

    private AvailVersion[] packAvailVersionsCache(string packname) @trusted
    {
        import std.algorithm : map, filter, sort;
        import std.array : array;
        import std.file : dirEntries, exists, isDir, SpanMode;
        import std.path : baseName;

        auto dir = cachePackDir(packname);
        if (!exists(dir) || !isDir(dir))
            return [];

        auto vers = dirEntries(dir, SpanMode.shallow)
            .map!(e => baseName(e.name))
            .filter!(s => Semver.isValid(s))
            .map!(v => AvailVersion(Semver(v), DepLocation.cache))
            .array;
        vers.sort!((a, b) => a > b);
        return vers;
    }

    private AvailVersion[] packAvailVersionsNetwork(string packname) @trusted
    {
        import std.algorithm : map;
        import std.array : array;
        import std.exception : enforce;

        auto pack = packagePayload(packname);
        auto resp = api().getPackageVersions(pack.id, false);
        enforce(resp.code != 404, new NoSuchPackageException(packname));
        return resp.payload.map!(v => AvailVersion(Semver(v), DepLocation.network)).array;
    }

    Recipe packRecipe(string packname, const(AvailVersion) aver, string revision = null) @system
    in (_network || aver.location != DepLocation.network, "Network access is disabled")
    {
        if (revision)
        {
            auto recipe = packRecipeMem(packname, aver.ver, revision);
            if (recipe)
            {
                return recipe;
            }
        }

        Recipe recipe;

        final switch (aver.location)
        {
        case DepLocation.cache:
            recipe = packRecipeCache(packname, aver.ver, revision);
            break;
        case DepLocation.network:
            recipe = packRecipeNetwork(packname, aver.ver, revision);
            break;
        case DepLocation.system:
            assert(false);
        }

        if (recipe)
        {
            memRecipe(recipe);
            return recipe;
        }

        throw verOrRevException(packname, aver.ver, revision);
    }

    private void memRecipe(Recipe recipe)
    {
        const id = depId(recipe.name, recipe.ver, recipe.revision);
        _recipeMem[id] = recipe;
    }

    private Recipe packRecipeMem(string packname, const ref Semver ver, string revision)
    {
        const id = depId(packname, ver, revision);

        if (auto p = id in _recipeMem)
            return *p;

        return Recipe.init;
    }

    private Recipe packRecipeCache(string packname, const ref Semver ver, string revision)
    {
        if (!revision)
            return findRecipeCache(packname, ver);

        const dir = cacheRevDir(packname, ver, revision);
        if (dir.hasRecipeFile)
            return Recipe.parseFile(dir.recipeFile, revision);

        return Recipe.init;
    }

    private Recipe findRecipeCache(string packname, const ref Semver ver)
    {
        import std.file : dirEntries, exists, SpanMode;
        import std.path : baseName;
        import std.stdio : File, LockType;

        const verDir = cacheVerDir(packname, ver);

        if (!exists(verDir))
            return Recipe.init;

        // FIXME: there is a tight coupling between this algorithm
        // and dopamine.paths.
        // Logic of discovery of revisions and associated lock file
        // should be moved to dopamine.paths.
        // (but actual file interaction left here)
        foreach (entry; dirEntries(verDir, SpanMode.shallow))
        {
            if (!entry.isDir)
                continue;

            const revDir = PackageDir(entry.name);

            if (revDir.hasRecipeFile)
            {
                const revLock = revDir.dir ~ ".lock";
                if (!exists(revLock))
                {
                    logWarning(
                        "%s %s-%s/%s was cached without lock file",
                        warning("Warning:"), packname, ver, baseName(revDir.dir)
                    );
                    auto f = File(revLock, "w");
                    f.close();
                }

                auto lock = File(revLock, "r");
                lock.lock(LockType.read);

                return Recipe.parseFile(revDir.recipeFile);
            }
        }
        return Recipe.init;
    }

    private Recipe packRecipeNetwork(string packname, const ref Semver ver, string revision = null)
    {
        import std.exception : enforce;
        import std.file : mkdirRecurse, write;
        import std.path : dirName;
        import std.stdio : File;

        auto pack = packagePayload(packname);
        auto resp = api().getRecipe(PackageRecipeGet(pack.id, ver.toString(), revision));
        enforce(resp.code != 404, verOrRevException(packname, ver, revision));

        if (revision)
            enforce(revision == resp.payload.rev);
        else
            revision = resp.payload.rev;

        const dir = cacheRevDir(packname, ver, revision);
        const lockF = cacheRevLock(packname, ver, revision);

        mkdirRecurse(dirName(lockF));

        auto lock = File(lockF, "w");
        lock.lock();

        mkdirRecurse(dir.dir);
        write(dir.recipeFile, resp.payload.recipe);

        return Recipe.parseFile(dir.recipeFile, revision);
    }

    private string depId(string packname, Semver ver, string revision) @safe
    {
        pragma(inline, true);

        import std.format : format;

        return format("%s-%s/%s", packname, ver, revision);
    }

    private DependencyException verOrRevException(string packname, const ref Semver ver, string revision)
    {
        return revision ?
            new NoSuchRevisionException(packname, ver, revision) : new NoSuchVersionException(packname, ver);
    }

    private PackagePayload packagePayload(string packname) @trusted
    in (_network)
    {
        import std.exception : enforce;

        if (auto p = packname in _packMem)
            return *p;

        auto resp = api().getPackageByName(packname);
        enforce(resp.code != 404, new NoSuchPackageException(packname));
        auto pack = resp.payload;
        _packMem[packname] = pack;
        return pack;
    }
}
