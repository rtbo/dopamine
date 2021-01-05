module dopamine.depcache;

import dopamine.api;
import dopamine.depdag;
import dopamine.dependency;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.semver;

class DependencyException : Exception
{
    this(string msg) @safe
    {
        super(msg);
    }
}

class NoSuchPackageException : DependencyException
{
    string packname;

    this(string packname) @safe
    {
        import std.format : format;

        this.packname = packname;
        super(format("No such package: %s", packname));
    }
}

class NoSuchVersionException : DependencyException
{
    string packname;
    const(Semver) ver;

    this(string packname, const(Semver) ver) @safe
    {
        import std.format : format;

        this.packname = packname;
        this.ver = ver;
        super(format("No such package version: %s-%s", packname, ver));
    }
}

final class DependencyCache : CacheRepo
{
    import std.typecons : Rebindable;

    private alias RcRecipe = Rebindable!(const(Recipe));

    private Package[string] _packageCache;
    private RcRecipe[string] _recipeCache;

    private this() @safe
    {
    }

    static @property DependencyCache get() @safe
    {
        return instance;
    }

    /// Get the recipe of a package in its specified version
    /// Params:
    ///     packname = name of the package
    ///     ver = version of the package
    /// Returns: The recipe of the package
    /// Throws: ServerDownException, NoSuchPackageException, NoSuchPackageVersionException
    const(Recipe) packRecipe(string packname, const(Semver) ver) @safe
    {
        import std.exception : enforce;
        import std.file : exists;
        import std.path : buildPath;

        const id = depId(packname, ver);

        if (auto p = id in _recipeCache)
            return *p;

        const dir = buildPath(userPackagesDir(), id);

        if (exists(dir))
        {
            const pd = PackageDir.enforced(dir);
            const r = recipeParseFile(pd.dopamineFile());
            _recipeCache[id] = r;
            return r;
        }

        // must go through API
        Package pack = getPackageMemOrNetwork(packname);
        auto resp = API().getPackageVersion(pack.id, ver.toString());
        enforce(resp.code != 404, new NoSuchVersionException(packname, ver));
        const recipe = resp.payload.recipe;

        _recipeCache[id] = recipe;
        return recipe;
    }

    /// Get the available versions of a package
    /// Params:
    ///     packname = name of the package
    /// Returns: the list of versions available of the package
    /// Throws: ServerDownException, NoSuchPackageException
    Semver[] packAvailVersions(string packname) @safe
    {
        import std.algorithm : map;
        import std.array : array;

        return getPackageMemOrNetwork(packname).versions.map!(v => Semver(v)).array;
    }

    /// Check whether a package version is in local cache or not
    /// Params:
    ///     packname = name of the package
    ///     ver = version of the package
    /// Retruns: whether the package is in local cache
    bool packIsCached(string packname, const(Semver) ver) @safe
    {
        import std.file : exists;
        import std.path : buildPath;

        const id = depId(packname, ver);
        const dir = buildPath(userPackagesDir(), id);

        if (exists(dir))
        {
            PackageDir.enforced(dir);
            return true;
        }

        return false;
    }

    /// Cache a dependency in the local cache
    /// Params:
    ///     packname = the name of the package
    ///     ver = version of the package
    /// Returns the recipe of the cached package
    const(Recipe) cachePackage(string packname, const(Semver) ver) @safe
    {
        import std.file : exists, mkdirRecurse;
        import std.path : buildPath;

        const id = depId(packname, ver);
        const dir = buildPath(userPackagesDir(), id);

        if (exists(dir))
        {
            const pd = PackageDir.enforced(dir);
            const r = recipeParseFile(pd.dopamineFile());
            _recipeCache[id] = r;
            return r;
        }

        const recipe = getRecipeMemOrNetwork(packname, ver, id);

        logInfo("Caching %s", info(id));

        mkdirRecurse(userPackagesDir());
        recipe.repo.fetchInto(dir);
        const pd = PackageDir.enforced(dir);
        const r = recipeParseFile(pd.dopamineFile());
        _recipeCache[id] = r;
        return r;
    }
    
    private string depId(string packname, const(Semver) ver) @safe
    {
        return packname ~ "-" ~ ver.toString();
    }

    private Package getPackageMemOrNetwork(string packname) @safe
    {
        import std.exception : enforce;

        if (auto p = packname in _packageCache)
            return *p;

        auto resp = API().getPackageByName(packname);
        enforce(resp.code != 404, new NoSuchPackageException(packname));
        auto pack = resp.payload;
        _packageCache[packname] = pack;
        return pack;
    }

    private const(Recipe) getRecipeMemOrNetwork(string packname, Semver ver, string id) @safe
    {
        import std.exception : enforce;

        if (auto p = id in _recipeCache)
            return *p;

        auto pack = getPackageMemOrNetwork(packname);
        auto resp = API().getPackageVersion(pack.id, ver.toString());
        enforce(resp.code != 404, new NoSuchVersionException(packname, ver));
        const recipe = resp.payload.recipe;
        _recipeCache[id] = recipe;
        return recipe;
    }
}

private:

DependencyCache instance;

static this()
{
    instance = new DependencyCache;
}
