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

// RecipeDir is still WIP. More logic from the client could be moved here.

/// RecipeDir is an abstraction over a recipe directory.
/// It contain the recipe itself and manage the state:
///  - the source code
///  - the build
///  - the activated profile
///  - etc.
///
/// In a nutshell:
///  - Recipe knows a to get the source and build the software and could do it anywhere.
///  - RecipeDir is tied to a particular location (project dir or cache dir) and manage the recipe
///    and package state at this locaiton.
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
            recipe = parseDopRecipe(dopFile, null);

        return RecipeDir(recipe, root);
    }

    bool opCast(T : bool)() const
    {
        return recipe !is null;
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
        return RecipeDir(recipe, buildNormalizedPath(absolutePath(_root, base)));
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

    /// Get the recipe of this directory.
    /// May be null if the directory has no recipe.
    @property inout(Recipe) recipe() inout
    {
        return _recipe;
    }

    /// Get all the files included in the recipe, included the recipe file itself.
    /// The caller must ensure that current directory is set to the recipe root directory.
    /// Returns: A range to the recipe files, sorted and relative to the recipe directory.
    const(string)[] getAllRecipeFiles() @system
    in (recipe !is null, "Not a recipe directory")
    in (recipe.isDop, "Function only meaningful for Dopamine recipes")
    in (
        buildNormalizedPath(getcwd()) == buildNormalizedPath(_root.absolutePath()),
        "getAllRecipeFiles must be called from the recipe root dir"
    )
    {
        import std.algorithm : map, sort, uniq;
        import std.array : array;
        import std.range : only, chain;

        const cwd = buildNormalizedPath(getcwd());

        auto files = only(recipeFile)
            .chain(recipe.include())
            .map!((f) {
                // normalize paths relative to root
                const a = buildNormalizedPath(absolutePath(f, cwd));
                return relativePath(a, cwd);
            })
            .array;

        sort(files);

        // ensure no file is counted twice (e.g. git ls-files will also include the recipe file)
        return files.uniq().array;
    }

    /// Compute the revision of the recipe. That is the SHA-1 checksum of all the files
    /// included in the recipe, truncated to 8 bytes and encoded in lowercase hexadecimal.
    /// The caller must ensure that current directory is set to the recipe root directory.
    /// `calcRecipeRevision` effectively assign recipe.revision and returns it.
    string calcRecipeRevision() @system
    in (recipe !is null, "Not a recipe directory")
    in (recipe.isDop, "Function only meaningful for Dopamine recipes")
    in (
        buildNormalizedPath(getcwd()) == buildNormalizedPath(_root.absolutePath()),
        "calcRecipeRevision must be called from the recipe root dir"
    )
    out (rev; rev.length && recipe.revision == rev)
    {
        import std.digest.sha;
        import squiz_box : readBinaryFile;

        auto dig = makeDigest!SHA1();
        ubyte[8192] buf;

        foreach (fn; getAllRecipeFiles())
        {
            foreach (chunk; readBinaryFile(fn, buf[]))
                dig.put(chunk);
        }

        const sha1 = dig.finish();
        recipe.revision = toHexString!(LetterCase.lower)(sha1[0 .. 8]).idup;
        return recipe.revision;
    }

    @property PkgStateFile stateFile()
    {
        return PkgStateFile(dopPath("state.json"));
    }

    string checkSourceReady(out string reason)
    out(dir; !dir || !std.path.isAbsolute(dir))
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
        return BuildPaths(_root, hash);
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
    private string _hash;

    private this(string root, string hash)
    {
        _root = root;
        _hash = hash;
    }

    bool opCast(T : bool)() const
    {
        return _root.length;
    }

    @property bool isAbsolute() const
    {
        return std.path.isAbsolute(_root);
    }

    BuildPaths asAbsolute(lazy string base = getcwd()) const
    {
        return BuildPaths(buildNormalizedPath(_root.absolutePath(base)), _hash);
    }

    @property string root() const
    {
        return _root;
    }

    @property string dop() const
    {
        return buildPath(_root, ".dop");
    }

    @property string hash() const
    {
        return _hash;
    }

    @property string build() const
    {
        return buildPath(_root, ".dop", _hash ~ "-build");
    }

    @property string install() const
    {
        return buildPath(_root, ".dop", _hash);
    }

    @property string lock() const
    {
        return buildPath(_root, ".dop", _hash ~ ".lock");
    }

    @property string state() const
    {
        return buildPath(_root, ".dop", _hash ~ "-state.json");
    }

    @property BuildStateFile stateFile() const
    {
        return BuildStateFile(state);
    }
}
