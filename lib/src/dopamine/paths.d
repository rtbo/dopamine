module dopamine.paths;

import dopamine.build_id;
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
    import std.datetime.systime : SysTime;

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

    @property SysTime recipeLastModified() const
    {
        import std.file : timeLastModified;

        if (!hasRecipeFile)
            return SysTime.max;

        return timeLastModified(recipeFile);
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

    ConfigDir configDir(const(BuildConfig) config) const
    {
        return ConfigDir(_dopPath(_configDirName(config)), this);
    }

    private static bool hasFile(string path)
    {
        import std.file : exists, isFile;

        return exists(path) && isFile(path);
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

    private string _configDirName(const(BuildConfig) config) const
    {
        return config.digestHash[0 .. 10];
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

/// Directory of a build configuration
struct ConfigDir
{
    private string _dir;
    private RecipeDir _recipeDir;

    @property string dir() const
    {
        return _dir;
    }

    @property RecipeDir recipeDir() const
    {
        return _recipeDir;
    }

    @property string lockFile() const
    {
        return _dir ~ ".lock";
    }

    @property ConfigStateFile stateFile() const
    {
        return ConfigStateFile(_dir ~ ".json");
    }
}

alias ConfigStateFile = JsonStateFile!ConfigState;

/// Content of the state relative to a build configuration
struct ConfigState
{
    string build;
}

@("RecipeDir.recipeFile")
unittest
{
    const dir = RecipeDir(".");
    assert(dir.recipeFile == buildPath(".", "dopamine.lua"));
}
