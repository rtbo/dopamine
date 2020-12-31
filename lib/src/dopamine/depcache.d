module dopamine.depcache;

import dopamine.api;
import dopamine.depdag;
import dopamine.dependency;
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

class NoSuchPackageDependencyException : DependencyException
{
    string packname;

    this(string packname) @safe
    {
        import std.format : format;

        this.packname = packname;
        super(format("No such package: %s", packname));
    }
}

class NoSuchVersionDependencyException : DependencyException
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
    ///     cache = whether the package version should be added to the package cache
    /// Returns: The recipe of the package
    /// Throws: ServerDownException, NoSuchPackageException, NoSuchPackageVersionException
    const(Recipe) packRecipe(string packname, const(Semver) ver, bool cache) @safe
    {
        import std.exception : enforce;
        import std.file : exists, isDir;
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
        auto api = API();
        Package pack;
        if (auto p = packname in _packageCache)
        {
            pack = *p;
        }
        else
        {
            auto packResp = api.getPackageByName(packname);
            enforce(packResp.code != 404, new NoSuchPackageDependencyException(packname));
            pack = packResp.payload;
            _packageCache[packname] = pack;
        }

        auto resp = api.getPackageVersion(pack.id, ver.toString());
        enforce(resp.code != 404, new NoSuchVersionDependencyException(packname, ver));
        const recipe = resp.payload.recipe;

        if (cache)
        {
            import std.file : mkdirRecurse;

            mkdirRecurse(userPackagesDir());
            recipe.repo.fetchInto(dir);
            const pd = PackageDir.enforced(dir);
            const r = recipeParseFile(pd.dopamineFile());
            _recipeCache[id] = r;
            return r;
        }

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

        auto api = API();
        const pack = api.getPackageByName(packname).payload;
        return pack.versions.map!(v => Semver(v)).array;
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

    private string depId(string packname, const(Semver) ver) @safe
    {
        return packname ~ "-" ~ ver.toString();
    }
}

private:

DependencyCache instance;

static this()
{
    instance = new DependencyCache;
}
