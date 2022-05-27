module dopamine.paths;

import dopamine.build_id;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

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

string homeLuaScript()
{
    import dopamine.conf : DOP_BUILD_ID;

    return buildPath(homeDopDir(), format("dop-%s.lua", DOP_BUILD_ID));
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
        _dir = buildNormalizedPath(absolutePath(dir));
        _dopDir = dopDir ? absolutePath(dopDir) : buildPath(_dir, ".dop");
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

    @property string lockPath() const
    {
        return _dopPath("lock");
    }

    @property string dopDir() const
    {
        return _dopDir;
    }

    ConfigDirs configDirs(const(BuildConfig) config) const
    {
        return ConfigDirs(this, config.digestHash[0 .. 10]);
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

    package string _dopPath(C...)(C comps) const
    {
        return buildPath(_dopDir, comps);
    }

    private string _dir;
    private string _dopDir;
}

/// Directories of a build configuration
struct ConfigDirs
{
    private RecipeDir _recipeDir;
    private string _hash;

    @property string buildDir() const
    {
        return _recipeDir._dopPath(_hash) ~ "-build";
    }

    @property string installDir() const
    {
        return _recipeDir._dopPath(_hash);
    }

    @property RecipeDir recipeDir() const
    {
        return _recipeDir;
    }

    @property string lockPath() const
    {
        return _recipeDir._dopPath(_hash ~ ".lock");
    }

    @property string statePath() const
    {
        return _recipeDir._dopPath(_hash ~ ".json");
    }
}

@("RecipeDir.recipeFile")
unittest
{
    const dir = RecipeDir(".");
    assert(buildNormalizedPath(dir.recipeFile) == buildNormalizedPath(absolutePath(buildPath(".", "dopamine.lua"))));
}
