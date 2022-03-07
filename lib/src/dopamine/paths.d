module dopamine.paths;

import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;
import dopamine.util;

import std.file;
import std.format;
import std.path;

@safe:

string homeDopDir()
{
    import std.process : environment;

    const home = environment.get("DOP_HOME");
    if (home)
        return home;

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

string homeProfilesDir()
{
    return buildPath(homeDopDir(), "profiles");
}

string homeProfileFile(string name)
{
    return buildPath(homeProfilesDir(), name ~ ".ini");
}

string homeProfileFile(Profile profile)
{
    return homeProfileFile(profile.name);
}

string userLoginFile()
{
    return buildPath(homeDopDir(), "login.json");
}

string homeCacheDir()
{
    return buildPath(homeDopDir(), "cache");
}

struct RecipeDir
{
    this(string dir, string dopDir = null)
    {
        import std.path : buildPath;

        _dir = dir;
        _dopDir = dopDir ? dopDir : buildPath(dir, ".dop");
    }

    @property string dir() const
    {
        return _dir;
    }

    @property bool exists() const
    {
        import std.file : exists, isDir;

        return dir.exists && dir.isDir;
    }

    @property bool hasRecipeFile() const
    {
        return hasFile(recipeFile);
    }

    @property string recipeFile() const
    {
        return _path("dopamine.lua");
    }

    @property bool hasProfileFile() const
    {
        return hasFile(profileFile);
    }

    @property string profileFile() const
    {
        return _dopPath("profile.ini");
    }

    @property bool hasDepsLockFile() const
    {
        return hasFile(depsLockFile);
    }

    @property string depsLockFile() const
    {
        return _path("dop.lock");
    }

    @property string lockFile() const
    {
        return _dopPath("lock");
    }

    @property string dopDir() const
    {
        return _dopDir;
    }

    @property PkgStateFile stateFile() const
    {
        return PkgStateFile(_dopPath("state.json"));
    }

    private static bool hasFile(string path)
    {
        import std.file : exists, isFile;

        return exists(path) && isFile(path);
    }

    @property ProfileDirs profileDirs(const(Profile) profile) const
    {
        const dirName = _configDirName(profile);

        ProfileDirs cdir;
        cdir.work = _dopPath(dirName);
        cdir.build = _dopPath(dirName, "build");
        cdir.install = _dopPath(dirName, "install");
        return cdir;
    }

    /// Get the path to the packed archive
    /// Must be called from the package dir
    string archiveFile(const(Profile) profile, const(Recipe) recipe) const
    in (profile && recipe)
    {
        import dopamine.archive : ArchiveBackend;

        import std.algorithm : findAmong;
        import std.exception : enforce;
        import std.format : format;

        const supportedFormats = ArchiveBackend.get.supportedExts;
        const preferredFormats = [".tar.xz", ".tar.bz2", ".tar.gz"];

        const archiveFormat = findAmong(preferredFormats, supportedFormats);

        enforce(archiveFormat.length, "No archive capability");

        const dirName = _configDirName(profile);
        const filename = format("%s-%s.%s%s", recipe.name, recipe.ver,
            profile.digestHash[0 .. 10], archiveFormat[0]);
        return _dopPath(dirName, filename);
    }

    static RecipeDir enforced(string dir, lazy string msg = null)
    {
        import std.exception : enforce;
        import std.format : format;

        const pdir = RecipeDir(dir);
        enforce(pdir.hasRecipeFile, msg.length ? msg
                : format("%s is not a Dopamine package directory", absolutePath(pdir.dir)));
        return pdir;
    }

    private string _path(C...)(C comps) const
    {
        return buildPath(_dir, comps);
    }

    private string _dopPath(C...)(C comps) const
    {
        return buildPath(_dopDir, comps);
    }

    private string _configDirName(const(Profile) profile) const
    {
        return profile.digestHash[0 .. 10];
    }

    private string _dir;
    private string _dopDir;
}

alias PkgStateFile = JsonStateFile!PkgState;

/// Content of the main state for the package dir state
struct PkgState
{
    string srcDir;
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

    /// Return a BuildDirs object to pass to the recipe for building and packaging
    BuildDirs buildDirs(in string src, in string base = getcwd()) const
    {
        import std.path : absolutePath;

        return BuildDirs(src.absolutePath(base), work.absolutePath(base),
            build.absolutePath(base), install.absolutePath(base));
    }
}

@("RecipeDir.recipeFile")
unittest
{
    const dir = RecipeDir(".");
    assert(dir.recipeFile == buildPath(".", "dopamine.lua"));
}
