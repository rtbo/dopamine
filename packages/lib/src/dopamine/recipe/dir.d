module dopamine.recipe.dir;

import dopamine.build_id;
import dopamine.recipe;
import dopamine.recipe.dub;
import dopamine.util;

import std.datetime;
import std.exception;
import std.file;
import std.json;
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
///  - Recipe knows how to get the source and build the software and could do it anywhere.
///  - RecipeDir is tied to a particular location (project dir or cache dir) and manage the recipe
///    and package state at this locaiton.
struct RecipeDir
{
    Recipe _recipe;
    string _root;

    package(dopamine) this(Recipe recipe, string root)
    in (isAbsolute(root))
    {
        _recipe = recipe;
        _root = root;
    }

    static RecipeDir fromDir(string root)
    in (isAbsolute(root))
    {
        Recipe recipe;

        root = buildNormalizedPath(root);

        const dopFile = checkDopRecipeFile(root);
        if (dopFile)
            recipe = parseDopRecipe(dopFile, root, null);

        const dubFile = checkDubRecipeFile(root);
        if (dubFile)
            recipe = parseDubRecipe(dubFile, root);

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

    @property string optionFile() const
    {
        return dopPath("options.json");
    }

    @property bool hasOptionFile() const
    {
        const p = optionFile();
        return exists(p) && isFile(p);
    }

    OptionSet readOptionFile() const
    {
        auto json = readJsonOptions();
        OptionSet res;
        jsonToOptions(json, res);
        return res;
    }

    void writeOptionFile(const(OptionSet) opts) const
    {
        JSONValue[string] json;
        optionsToJson(opts, json);
        writeJsonOptions(json);
    }

    void clearOptionFile() const
    {
        const p = optionFile;
        if (exists(p) && isFile(p))
            remove(p);
    }

    OptionSet mergeOptionFile(return scope OptionSet opts) const
    {
        auto json = readJsonOptions();
        optionsToJson(opts, json);
        jsonToOptions(json, opts);
        writeJsonOptions(json);
        return opts;
    }

    private JSONValue[string] readJsonOptions() const
    {
        const p = optionFile();
        if (!exists(p) || !isFile(p))
            return null;
        auto json = cast(const(char)[]) read(p);
        return parseJSON(json).objectNoRef;
    }

    private void writeJsonOptions(JSONValue[string] json) const
    {
        import std.string : representation;

        mkdirRecurse(dopPath());
        const str = JSONValue(json).toPrettyString();
        write(optionFile, str.representation);
    }

    private void jsonToOptions(const(JSONValue[string]) json, ref OptionSet opts) const
    {
        foreach (string key, const ref JSONValue val; json)
        {
            switch (val.type)
            {
            case JSONType.true_:
                opts[key] = OptionVal(true);
                break;
            case JSONType.false_:
                opts[key] = OptionVal(false);
                break;
            case JSONType.integer:
                opts[key] = OptionVal(val.get!int);
                break;
            case JSONType.string:
                opts[key] = OptionVal(val.get!string);
                break;
            default:
                throw new Exception("Invalid JSON option type in " ~ optionFile);
            }
        }
    }

    private static void optionsToJson(const(OptionSet) opts, ref JSONValue[string] json)
    {
        import std.sumtype : match;

        foreach (name, optVal; opts)
        {
            optVal.match!(
                (bool val) => json[name] = val,
                (int val) => json[name] = val,
                (string val) => json[name] = val,
            );
        }
    }

    /// Get the recipe of this directory.
    /// May be null if the directory has no recipe.
    @property inout(Recipe) recipe() inout
    {
        return _recipe;
    }

    /// Get all the files included in the recipe, included the recipe file itself.
    /// Returns: A range to the recipe files, sorted and relative to the recipe root directory.
    const(string)[] getAllRecipeFiles() @system
    in (recipe !is null, "Not a recipe directory")
    in (recipe.isDop, "Function only meaningful for Dopamine recipes")
    {
        import std.algorithm : map, sort, uniq;
        import std.array : array;
        import std.range : only, chain;

        auto files = only(recipeFile)
            .chain(recipe.include())
            .map!((f) {
                // normalize all paths relative to root
                const a = buildNormalizedPath(absolutePath(f, _root));
                return relativePath(a, _root);
            })
            .array;

        sort(files);

        // ensure no file is counted twice (e.g. git ls-files will also include the recipe file)
        return files.uniq().array;
    }

    /// Compute the revision of the recipe. That is the SHA-1 checksum of all the files
    /// included in the recipe, truncated to 8 bytes and encoded in lowercase hexadecimal.
    /// `calcRecipeRevision` effectively assign recipe.revision and returns it.
    string calcRecipeRevision() @system
    in (recipe !is null, "Not a recipe directory")
    in (recipe.isDop, "Function only meaningful for Dopamine recipes")
    out (rev; rev.length && recipe.revision == rev)
    {
        import std.digest.sha;
        import squiz_box : readBinaryFile;

        auto dig = makeDigest!SHA1();
        ubyte[8192] buf;

        foreach (fn; getAllRecipeFiles())
        {
            foreach (chunk; readBinaryFile(path(fn), buf[]))
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
    out (dir; !dir || !std.path.isAbsolute(dir))
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

string checkDopRecipeFile(string dir) @safe
{
    const dopFile = buildPath(dir, "dopamine.lua");
    if (exists(dopFile) && isFile(dopFile))
        return dopFile;
    return null;
}

string checkDubRecipeFile(string dir) @safe
{
    string[3] recipeFileNames = ["dub.json", "dub.sdl", "package.json"];

    foreach (fn; recipeFileNames)
    {
        const dubFile = buildPath(dir, fn);
        if (exists(dubFile) && isFile(dubFile))
            return dubFile;
    }

    return null;
}

struct BuildPaths
{
    private string _root;
    private string _hash;

    private this(string root, string hash)
    in (isAbsolute(root))
    {
        _root = root;
        _hash = hash;
    }

    bool opCast(T : bool)() const
    {
        return _root.length;
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
