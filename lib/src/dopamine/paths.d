module dopamine.paths;

import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;
import dopamine.util;

import std.file;
import std.format;
import std.path;

@safe:

string userDopDir()
{
    import std.process : environment;

    version (linux)
    {
        return buildPath(environment["HOME"], ".dopamine");
    }
    else version (Windows)
    {
        return buildPath(environment["LOCALAPPDATA"], "Dopamine");
    }
    else
    {
        static assert(false, "unsupported OS");
    }
}

string userPackagesDir()
{
    return buildPath(userDopDir(), "packages");
}

string userPackageDir(string packname, const(Semver) ver)
{
    return buildPath(userDopDir(), "packages", format("%s-%s", packname, ver));
}

string userProfilesDir()
{
    return buildPath(userDopDir(), "profiles");
}

string userProfileFile(string name)
{
    return buildPath(userProfilesDir(), name ~ ".ini");
}

string userProfileFile(Profile profile)
{
    return userProfileFile(profile.name);
}

string userProfileDepsInstall(Profile profile)
{
    return buildPath(userDopDir, "deps", format("%s-%s",
            profile.digestHash[0 .. 10], profile.name));
}

string userLoginFile()
{
    return buildPath(userDopDir(), "login.json");
}

string cacheDepPackDir(string packname)
{
    return buildPath(userDopDir(), "packages", packname);
}

string cacheDepVerDir(string packname, Semver ver)
{
    return buildPath(userDopDir(), "packages", packname, ver.toString());
}

PackageDir cacheDepRevDir(string packname, Semver ver, string revision)
{
    return PackageDir(buildPath(userDopDir(), "packages", packname, ver.toString(), revision));
}

FlagFile cacheDepRevDirFlag(string packname, Semver ver, string revision)
{
    return FlagFile(buildPath(userDopDir(), "packages", packname, ver.toString(), "." ~ revision));
}

PackageDir cacheDepRevDir(Recipe recipe) @system
{
    return cacheDepRevDir(recipe.name, recipe.ver, recipe.revision());
}

FlagFile cacheDepRevDirFlag(Recipe recipe) @system
{
    return cacheDepRevDirFlag(recipe.name, recipe.ver, recipe.revision());
}

struct PackageDir
{
    private string _dir;

    @property string dir() const
    {
        return _dir;
    }

    @property bool exists() const
    {
        import std.file : exists, isDir;

        return exists(dir) && isDir(dir);
    }

    @property bool hasDopamineFile() const
    {
        import std.file : exists, isFile;

        const df = _path("dopamine.lua");
        return exists(df) && isFile(df);
    }

    @property string dopamineFile() const
    {
        return _path("dopamine.lua");
    }

    @property string lockFile() const
    in(hasDopamineFile)
    {
        return _path("dop.lock");
    }

    @property string dopDir() const
    in(hasDopamineFile)
    {
        return _path(".dop");
    }

    @property FlagFile sourceFlag() const
    in(hasDopamineFile)
    {
        return FlagFile(_path(".dop", ".source"));
    }

    @property string profileFile() const
    in(hasDopamineFile)
    {
        return _path(".dop", "profile.ini");
    }

    /// Get the default locations for building with profile
    ProfileDirs profileDirs(const(Profile) profile) const @trusted
    in(profile && hasDopamineFile)
    {
        const workDir = _workDirName(profile);

        ProfileDirs dirs = void;
        dirs.work = _path(".dop", workDir);
        dirs.build = _path(".dop", workDir, "build");
        dirs.install = _path(".dop", workDir, "install");
        return dirs;
    }

    /// Get the path to the packed archive
    /// Must be called from the package dir
    string archiveFile(const(Profile) profile, const(Recipe) recipe) const
    in(profile && recipe && hasDopamineFile)
    {
        import dopamine.archive : ArchiveBackend;

        import std.algorithm : findAmong;
        import std.exception : enforce;
        import std.format : format;

        const supportedFormats = ArchiveBackend.get.supportedExts;
        const preferredFormats = [".tar.xz", ".tar.bz2", ".tar.gz"];

        const archiveFormat = findAmong(preferredFormats, supportedFormats);

        enforce(archiveFormat.length, "No archive capability");

        const workDir = _workDirName(profile);
        const filename = format("%s-%s.%s%s", recipe.name, recipe.ver,
                profile.digestHash[0 .. 10], archiveFormat[0]);
        return _path(".dop", workDir, filename);
    }

    FlagFile archiveFlag(const(Profile) profile) const
    {
        const workDir = _workDirName(profile);
        return FlagFile(_path(".dop", workDir, ".archive"));

    }

    static PackageDir enforced(string dir, lazy string msg = null)
    {
        import std.exception : enforce;

        const pdir = PackageDir(dir);
        enforce(pdir.hasDopamineFile, msg.length ? msg
                : format("%s is not a Dopamine package directory", pdir.dir));
        return pdir;
    }

    private string _path(Args...)(Args comps) const @trusted
    {
        import std.array : array;
        import std.exception : assumeUnique;

        return assumeUnique(asNormalizedPath(chainPath(dir, comps)).array);
    }

    private static string _workDirName(const(Profile) profile)
    {
        return profile.digestHash[0 .. 10];
    }
}

/// Structure gathering directories needed during a build
struct ProfileDirs
{
    /// dop working directory
    string work;
    /// Directory recommendation for the build
    string build;
    /// directory into which files are installed
    string install;

    /// FlagFile that indicates that build is done and contain the directory
    FlagFile buildFlag() const
    {
        return FlagFile(buildPath(work, ".build"));
    }

    /// FlagFile that tracks installation of dependencies
    FlagFile depsFlag() const
    {
        return FlagFile(buildPath(work, ".deps"));
    }

    /// Return a BuildDirs object to pass to the recipe for building and packaging
    BuildDirs buildDirs(in string src, in string base = getcwd()) const
    {
        return BuildDirs(src.absolutePath(base), work.absolutePath(base),
                build.absolutePath(base), install.absolutePath(base));
    }
}
