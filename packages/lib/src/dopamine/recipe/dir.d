module dopamine.recipe.dir;

import dopamine.build_id;
import dopamine.recipe;
import dopamine.util;

import std.datetime;
import std.exception;
import std.file;
import std.path;

/// Content of the main state for the package dir state
struct PkgState
{
    string srcDir;
}

alias PkgStateFile = JsonStateFile!PkgState;

/// Content of the state relative to a build configuration
struct BuildState
{
    import std.datetime : SysTime;

    SysTime buildTime;

    bool opCast(T : bool)() const
    {
        return !!buildDir;
    }
}

alias BuildStateFile = JsonStateFile!BuildState;

struct RecipeDir
{
    Recipe _recipe;
    string _root;

    package(dopamine) this(Recipe recipe, string root)
    {
        _recipe = recipe;
        _root = root;
    }

    static RecipeDir fromDir(string root)
    {
        Recipe recipe;

        const dopFile = checkDopRecipeFile(root);
        if (dopFile)
            recipe = new DopRecipe(dopFile, null);

        return RecipeDir(recipe, root);
    }

    static RecipeDir enforceFromDir(string root)
    {
        auto rdir = fromDir(root);
        enforce(rdir.recipe, absolutePath(root) ~ " is not a Dopamine package directory");
        return rdir;
    }

    @property inout(Recipe) recipe() inout
    {
        return _recipe;
    }

    @property string root() const
    {
        return _root;
    }

    @property bool isAbsolute() const
    {
        return std.path.isAbsolute(_root);
    }

    RecipeDir asAbsolute(lazy string base = getcwd())
    {
        return RecipeDir(recipe, absolutePath(_root, base));
    }

    string path(Args...)(Args args) const
    {
        return buildPath(_root, args);
    }

    string dopPath(Args...)(Args args) const
    {
        return path(_root, ".dop", args);
    }

    @property string recipeFile() const
    {
        return path("dopamine.lua");
    }

    @property bool hasRecipeFile() const
    {
        const p = recipeFile;
        return exists(p) && isFile(p);
    }

    @property SysTime recipeLastModified() const
    {
        return timeLastModified(recipeFile);
    }

    @property string profileFile() const
    {
        return dopPath("profile.ini");
    }

    @property bool hasProfileFile() const
    {
        const p = profileFile;
        return exists(p) && isFile(p);
    }

    @property string depsLockFile() const
    {
        return path("dop.lock");
    }

    @property bool hasDepsLockFile() const
    {
        const p = depsLockFile;
        return exists(p) && isFile(p);
    }

    @property string lockFile() const
    {
        return dopPath("lock");
    }

    @property bool hasLockFile() const
    {
        const p = lockFile;
        return exists(p) && isFile(p);
    }

    @property PkgStateFile stateFile()
    {
        return PkgStateFile(dopPath("state.json"));
    }

    string checkSourceReady(out string reason)
    {
        if (!recipe)
        {
            reason = "Not a package directory";
            return null;
        }

        if (recipe.inTreeSrc)
        {
            const srcDir = recipe.source();
            return srcDir;
        }

        auto sf = stateFile;
        auto state = sf.read();
        if (!sf || !state.srcDir)
        {
            reason = "Source directory is not ready";
            return null;
        }

        if (sf.timeLastModified < recipeLastModified)
        {
            reason = "Source directory is not up-to-date";
            return null;
        }
        return state.srcDir;
    }

    BuildPaths buildPaths(BuildId buildId) const
    {
        const hash = buildId.uniqueId[0 .. 10];
        return BuildPaths(_root, dopPath(), hash);
    }

    bool checkBuildReady(BuildId buildId, out string reason)
    {
        const bPaths = buildPaths(buildId);

        if (!exists(bPaths.install))
        {
            reason = "Install directory doesn't exist: " ~ bPaths.install;
            return false;
        }

        if (!bPaths.state.exists())
        {
            reason = "Build config state file doesn't exist";
            return false;
        }

        const rtime = recipeLastModified;
        auto state = bPaths.stateFile.read();

        if (rtime >= bPaths.stateFile.timeLastModified ||
            rtime >= state.buildTime)
        {
            reason = "Build is not up-to-date";
            return false;
        }

        return true;
    }
}

string checkDopRecipeFile(string dir)
{
    const dopFile = buildPath(dir, "dopamine.lua");
    if (exists(dopFile) && isFile(dopFile))
        return dopFile;
    return null;
}

struct BuildPaths
{
    private string _root;
    private string _dop;
    private string _hash;

    private this(string root, string dop, string hash)
    {
        _root = root;
        _dop = dop;
        _hash = hash;
    }

    bool opCast(T: bool)() const
    {
        return _root.length;
    }

    @property string root() const
    {
        return _root;
    }

    @property string dop() const
    {
        return _dop;
    }

    @property string hash() const
    {
        return _hash;
    }

    @property string build() const
    {
        return buildPath(_dop, _hash ~ "-build");
    }

    @property string install() const
    {
        return buildPath(_dop, _hash);
    }

    @property string lock() const
    {
        return buildPath(_dop, _hash ~ ".lock");
    }

    @property string state() const
    {
        return buildPath(_dop, _hash ~ "-state.json");
    }

    @property BuildStateFile stateFile() const
    {
        return BuildStateFile(state);
    }
}
