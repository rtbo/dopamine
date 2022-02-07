module dopamine.dep.service;

import dopamine.api;
import dopamine.dep.resolved;
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
    Recipe packRecipe(string packname, const(Semver) ver, string rev = null);
}
