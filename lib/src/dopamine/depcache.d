module dopamine.depcache;

import dopamine.api;
import dopamine.depdag;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.typecons;

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
    private Package[string] _packageCache;
    private Recipe[string] _recipeCache;
    private Flag!"network" _network;

    this(Flag!"network" network = Yes.network)
    {
        _network = network;
    }

    /// Clean all recipes held in memory
    void dispose()
    {
        foreach (k, ref r; _recipeCache)
        {
            r = Recipe.init;
        }
        _recipeCache.clear();
        _recipeCache = null;
        _packageCache.clear();
        _packageCache = null;
    }

    /// Get the recipe of a package in its specified version
    /// Params:
    ///     packname = name of the package
    ///     ver = version of the package
    ///     revision = optional revision of the package
    /// Returns: The recipe of the package
    /// Throws: ServerDownException, NoSuchPackageException, NoSuchPackageVersionException
    Recipe packRecipe(string packname, Semver ver, string revision = null) @system
    {
        import std.exception : enforce;
        import std.file : exists;
        import std.path : buildPath;

        if (revision)
        {
            auto rid = getRecipeMemory(packname, ver, revision);
            auto recipe = rid[0];
            if (recipe)
            {
                return recipe;
            }
            const id = rid[1];

            recipe = getRecipeCache(packname, ver, revision);
            if (recipe)
            {
                _recipeCache[id] = recipe;
                return recipe;
            }
        }

        if (!revision || !_network)
        {
            auto recipe = findRecipeCache(packname, ver);
            if (recipe)
            {
                _recipeCache[depId(packname, ver, recipe.revision())] = recipe;
                return recipe;
            }
        }

        if (_network)
        {
            // must go through API
            auto recipe = cacheRecipeNetwork(packname, ver, revision);
            _recipeCache[depId(packname, ver, revision)] = recipe;
            return recipe;
        }

        throw new NoSuchVersionException(packname, ver);
    }

    /// Get the directory of a dependency package
    /// Params:
    ///     recipe = name of the package
    /// Returns: The PackageDir for this package
    PackageDir packDir(Recipe recipe) @system
    {
        return cacheDepRevDir(recipe);
    }

    /// Get the available versions of a package
    /// Params:
    ///     packname = name of the package
    /// Returns: the list of versions available of the package
    /// Throws: ServerDownException, NoSuchPackageException
    Semver[] packAvailVersions(string packname) @trusted
    out (res; res.length > 0)
    {
        import std.algorithm : map;
        import std.array : array;
        import std.exception : enforce;

        if (_network)
        {
            auto pack = getPackageMemOrNetwork(packname);
            auto resp = API().getPackageVersions(pack.id, false);
            enforce(resp.code != 404, new NoSuchPackageException(packname));
            return resp.payload.map!(v => Semver(v)).array;
        }
        else
        {
            return allVersionsCached(packname);
        }
    }

    /// Check whether a package version is in local cache or not
    /// Params:
    ///     packname = name of the package
    ///     ver = version of the package
    ///     revision = optional revision of the package
    /// Retruns: whether the package is in local cache
    bool packIsCached(string packname, Semver ver, string revision = null) @trusted
    {
        import std.file : dirEntries, SpanMode;
        import std.format : format;
        import std.path : buildPath;

        if (revision)
        {
            const dir = cacheDepRevDir(packname, ver, revision);
            return dir.hasDopamineFile;
        }
        else
        {
            const dir = buildPath(userPackagesDir(), format("%s-%s", packname, ver));
            foreach (e; dirEntries(dir, SpanMode.depth))
            {
                if (e.isFile && e.name == "dopamine.lua")
                    return true;
            }
            return false;
        }
    }

    private string depId(string packname, Semver ver, string revision) @safe
    {
        pragma(inline, true);

        import std.format : format;

        return format("%s-%s/%s", packname, ver, revision);
    }

    private Package getPackageMemOrNetwork(string packname) @trusted
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

    private Tuple!(Recipe, string) getRecipeMemory(string packname, Semver ver, string revision) @safe
    {
        string id = depId(packname, ver, revision);

        if (auto p = id in _recipeCache)
            return tuple(*p, id);

        return tuple(Recipe.init, id);
    }

    private Recipe getRecipeCache(string packname, Semver ver, string revision) @system
    {
        const dir = cacheDepRevDir(packname, ver, revision);
        if (dir.hasDopamineFile)
        {
            return Recipe.parseFile(dir.dopamineFile, revision);
        }
        return Recipe.init;
    }

    private Recipe findRecipeCache(string packname, Semver ver) @system
    {
        import std.algorithm : map, filter, sort;
        import std.array : array;
        import std.file : exists, isDir, dirEntries, SpanMode, DirEntry, timeLastModified;
        import std.path : baseName, buildPath, dirName;

        const dir = cacheDepVerDir(packname, ver);
        if (!exists(dir) || !isDir(dir))
            return Recipe.init;

        string flag(string rev)
        {
            return buildPath(dir, "." ~ rev);
        }

        auto revs = dirEntries(dir, SpanMode.shallow).filter!(e => e.isDir)
            .map!(e => baseName(e.name))
            .filter!(r => exists(flag(r)))
            .array;

        if (revs.length == 0)
            return Recipe.init;

        revs.sort!((a, b) => timeLastModified(flag(a)) > timeLastModified(flag(b)));

        return getRecipeCache(packname, ver, revs[0]);
    }

    private Semver[] allVersionsCached(string packname)
    {
        import std.algorithm : map, filter, sort;
        import std.array : array;
        import std.file : exists, isDir, dirEntries, SpanMode;
        import std.path : baseName;

        const packdir = cacheDepPackDir(packname);
        auto vers = dirEntries(packdir, SpanMode.shallow).filter!(e => e.isDir)
            .map!(e => baseName(e.name))
            .filter!(s => Semver.isValid(s))
            .map!(v => Semver(v))
            .array;
        vers.sort!((a, b) => a > b);
        return vers;
    }

    private Recipe cacheRecipeNetwork(string packname, Semver ver, string revision = null) @system
    {
        import std.exception : enforce;
        import std.file : mkdirRecurse, write;

        auto pack = getPackageMemOrNetwork(packname);
        auto resp = API().getRecipe(PackageRecipeGet(pack.id, ver.toString(), revision));
        enforce(resp.code != 404, new NoSuchVersionException(packname, ver));
        revision = resp.payload.rev;
        const dir = cacheDepRevDir(packname, ver, revision);
        mkdirRecurse(dir.dir);
        write(dir.dopamineFile, resp.payload.recipe);
        auto flag = cacheDepRevDirFlag(packname, ver, revision);
        flag.touch();
        return Recipe.parseFile(dir.dopamineFile, revision);
    }

}
