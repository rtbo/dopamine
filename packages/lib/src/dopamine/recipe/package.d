module dopamine.recipe;

import dopamine.build_id;
import dopamine.dep.spec;
import dopamine.profile;
import dopamine.semver;

import std.file;
import std.json;
import std.path;
import std.sumtype;

public import dopamine.recipe.dir;
public import dopamine.recipe.dop;

/// The value of an option can be bool, string or int
alias OptionVal = SumType!(bool, string, int);

/// A set of options.
/// A recipe can defines options for itself, or specify option values
/// for its dependencies.
/// OptionSet is an OptionVal dictionary. Keys are option names.
/// Options specified for dependencies must be prefixed with "pkgname/"
/// (forward slash acts as separator).
struct OptionSet
{
    private OptionVal[string] _opts;

    this(OptionVal[string] opts) @safe
    {
        _opts = opts;
    }

    this(const(JSONValue[string]) json) @trusted
    {
        import std.conv : to;

        foreach (string key, const ref JSONValue val; json)
        {
            switch (val.type)
            {
            case JSONType.true_:
                _opts[key] = OptionVal(true);
                break;
            case JSONType.false_:
                _opts[key] = OptionVal(false);
                break;
            case JSONType.integer:
                _opts[key] = OptionVal(val.get!int);
                break;
            case JSONType.string:
                _opts[key] = OptionVal(val.get!string);
                break;
            default:
                throw new Exception("Invalid JSON option type: " ~ val.type.to!string);
            }
        }
    }

    JSONValue[string] toJSON() const
    {
        import std.sumtype : match;

        JSONValue[string] json;

        foreach (name, opt; _opts)
        {
            opt.match!(
                (bool val) => json[name] = val,
                (int val) => json[name] = val,
                (string val) => json[name] = val,
            );
        }

        return json;
    }

    OptionVal get(string key, lazy OptionVal def) const @safe
    {
        return _opts.get(key, def);
    }

    OptionVal opIndex(string key) const @safe
    {
        return _opts[key];
    }

    OptionVal opIndexAssign(OptionVal val, string key) @trusted
    {
        return _opts[key] = val;
    }

    inout(OptionVal)* opBinaryRight(string op)(string key) inout @safe
    {
        static assert(op == "in", "only 'in' binary operator is defined");
        return key in _opts;
    }

    int opApply(scope int delegate(string key, OptionVal val) @safe dg) const @safe
    {
        foreach (k, v; _opts)
        {
            int res = dg(k, v);
            if (res)
                return res;
        }
        return 0;
    }

    int opApply(scope int delegate(string key, ref OptionVal val) @safe dg) @safe
    {
        foreach (k, ref v; _opts)
        {
            int res = dg(k, v);
            if (res)
                return res;
        }
        return 0;
    }

    bool remove(string key) @safe
    {
        return _opts.remove(key);
    }

    @property string[] keys() const @safe
    {
        return _opts.keys;
        // string[] res;
        // foreach (k; _opts)
        //     res ~= k;
        // res;
    }

    @property size_t length() const @safe
    {
        return _opts.length;
    }

    @property OptionSet dup() const @trusted
    {
        OptionVal[string] opts;
        foreach (k, v; _opts)
            opts[k] = v;

        return OptionSet(opts);
    }

    /// Return the keys that are present in both this set and the other set
    /// but for which the value is different
    string[] conflicts(const(OptionSet) other) const @safe
    {
        string[] res;
        foreach (k, v; _opts)
        {
            const ov = k in other;
            if (ov && *ov != v)
                res ~= k;
        }
        return res;
    }

    /// Retrieve all option values that are specified for the root dependency
    OptionSet forRoot() const @trusted
    {
        import std.algorithm : canFind;

        OptionVal[string] res;
        foreach (key, val; _opts)
        {
            if (!key.canFind('/'))
                res[key] = val;
        }
        return OptionSet(res);
    }

    /// Retrieve all option values that are specified for the given dependency
    /// The prefix [name/] is removed from keys in the returned dict.
    OptionSet forDependency(string name) const @trusted
    {
        import std.algorithm : startsWith;

        OptionVal[string] res;
        const prefix = name ~ "/";
        foreach (key, val; _opts)
        {
            if (key.startsWith(prefix))
                res[key[prefix.length .. $]] = val;
        }
        return OptionSet(res);
    }

    /// Retrieve all option values that are not specified for the root recipe
    OptionSet forDependencies() const @trusted
    {
        import std.algorithm : canFind;

        OptionVal[string] res;
        foreach (key, val; _opts)
        {
            if (key.canFind('/'))
                res[key] = val;
        }
        return OptionSet(res);
    }

    /// Retrieve all option values that are specified for another dependency
    /// than the provided one. Root names are excluded as well.
    OptionSet notFor(string name) const @trusted
    {
        import std.algorithm : canFind, startsWith;

        OptionVal[string] res;
        const prefix = name ~ "/";
        foreach (key, val; _opts)
        {
            if (!key.startsWith(prefix) && key.canFind('/'))
                res[key] = val;
        }
        return OptionSet(res);
    }

    /// Merge this set with the other sets in parameters.
    /// In case of conflicting options (same key but different values),
    /// the value of `this` is chosen, and the key is appended to the
    /// `conflicts` parameter.
    OptionSet merge(OS...)(ref string[] conflicts, OS otherSets) @trusted
    {
        OptionVal[string] res;

        static foreach (other; otherSets)
        {
            foreach (k, v; other._opts)
            {
                const tv = k in _opts;
                if (tv && *tv != v)
                    conflicts ~= k;
                else
                    res[k] = v;
            }
        }
        foreach (k, v; _opts)
            res[k] = v;

        return OptionSet(res);
    }

    /// Return the union of this set with the other sets in parameters.
    /// The values of this take precedence if the same key are found in multiple
    /// sets.
    OptionSet union_(OS...)(OS otherSets) @trusted
    {
        OptionVal[string] res;

        static foreach (other; otherSets)
        {
            foreach (k, v; other._opts)
            {
                res[k] = v;
            }
        }
        foreach (k, v; _opts)
            res[k] = v;

        return OptionSet(res);
    }
}

/// An Option as specified in the dependency.
/// Type is defined by defaultValue.
/// Name is not defined here because this struct is typically
/// held in an associative array.
struct Option
{
    OptionVal defaultValue;
    string description;
}

/// A recipe dependency specification
struct DepSpec
{
    string name;
    VersionSpec spec;
    bool dub;
    OptionSet options;

    @property DepSpec dup() const
    {
        return DepSpec(name, spec, dub, options.dup);
    }
}

/// Directories passed to the `build` recipe function
struct BuildDirs
{
    string root;
    string src;
    string build;
    string install;

    invariant
    {
        assert(root.isAbsolute);
        assert(src.isAbsolute);
        assert(build.isAbsolute);
        assert(install.isAbsolute);
    }
}

/// The build configuration
struct BuildConfig
{
    /// the build profile
    const(Profile) profile;

    OptionSet options;

    void feedDigest(D)(ref D digest) const
    {
        import dopamine.util : feedDigestData;
        import std.algorithm : sort;
        import std.sumtype : match;

        profile.feedDigest(digest);

        auto names = options.keys;
        sort(names);
        foreach (name; names)
        {
            feedDigestData(digest, name);
            options[name].match!(
                (bool val) => feedDigestData(digest, val),
                (int val) => feedDigestData(digest, val),
                (string val) => feedDigestData(digest, val),
            );
        }
    }
}

struct DepBuildInfo
{
    /// The name of the dependency package
    string name;
    /// Whether it is a DUB dependency
    bool dub;
    /// The version of the dependency package
    Semver ver;
    /// The build-id of the dependency package
    BuildId buildId;
    /// Where the dependency is install
    string installDir;
}

enum RecipeType
{
    /// A genuine dopamine recipe
    dop,
    /// A recipe for Dub
    dub,
}

interface Recipe
{
    /// The type of recipe
    @property RecipeType type() const @safe;

    /// Helper for the recipe type
    final @property bool isDop() const @safe
    {
        return type == RecipeType.dop;
    }

    /// ditto
    final @property bool isDub() const @safe
    {
        return type == RecipeType.dub;
    }

    /// Whether this is a light recipe,
    /// that is a recipe that only specifies dependencies to be staged
    @property bool isLight() const @safe;

    /// The package name
    @property string name() const @safe;

    /// The package version
    @property Semver ver() const @safe;

    /// The package revision
    @property string revision() const @safe;
    @property void revision(string rev) @safe;

    /// The description of the packaged software
    @property string description() const @safe;

    /// The license of the packaged software
    @property string license() const @safe;

    /// The upstream URL of the packaged software
    @property string upstreamUrl() const @safe;

    /// Return tools needed by this recipe.
    /// This will determine the toolchain needed to build the package.
    @property const(string)[] tools() const @safe;

    /// Return options declared by this recipe.
    /// This is not strictly needed to use options but serves two purposes:
    ///  - define default values.
    ///  - document options
    @property const(Option[string]) options() const @safe;

    /// Whether this recipe has dependencies.
    /// In case dependencies are only needed for some config cases, true is returned.
    @property bool hasDependencies() const @safe;

    /// Get the dependencies of the package for the given build configuration
    const(DepSpec)[] dependencies(const(Profile) profile) @system;

    /// Get the files to include with the recipe when publishing to registry.
    /// This is relative to the root recipe dir.
    /// The current directory (as returned by `getcwd`) must be the
    /// recipe root directory
    string[] include() @system;

    /// Checks whether the source code is provided with the recipe.
    /// In this case, `source` may return a path relative to the recipe
    /// root directory
    @property bool inTreeSrc() const @safe;

    /// Ensure that the source is present and return
    /// the directory to the source root dir.
    /// In case of out-of-tree source code (the recipe packages a 3rd party code),
    /// The `source` function effectively download and prepare the source code.
    /// The current directory (as returned by `getcwd`) must be the
    /// recipe root directory
    string source() @system
    in (!isLight, "Light recipes have no defined source");

    /// Build and install the package to the given directory and
    /// with provided config. Info about dependencies is also provided.
    /// The current directory (as returned by `getcwd`) must be the
    /// build directory (where to build object files or any intermediate file before installation).
    void build(BuildDirs dirs, const(BuildConfig) config, DepBuildInfo[string] depInfos = null) @system
    in (!isLight, "Light recipes do not build");

    /// Whether this recipe can stage an installation to another
    /// directory without rebuilding from source.
    @property bool canStage() const @safe;

    /// Stage an installation to another directory.
    /// The current directory (as returned by `getcwd`) must be the
    /// recipe root directory.
    void stage(string src, string dest) @system
    in (!isLight, "Light recipes do not stage")
    in (canStage, "Recipe can't stage");
}

version (unittest)  : final class MockRecipe : Recipe
{
    private string _name;
    private Semver _ver;
    private RecipeType _type;
    private string _rev;
    private DepSpec[] _deps;
    private string[] _tools;

    this(string name, Semver ver, RecipeType type, string rev, DepSpec[] deps, string[] tools)
    {
        _name = name;
        _ver = ver;
        _type = type;
        _rev = rev;
        _deps = deps;
        _tools = tools;
    }

    // FIXME: remove filename and rootDir to manage it in RecipeDir
    @property string filename() const @safe
    {
        return null;
    }

    @property string rootDir() const @safe
    {
        return null;
    }

    /// The type of recipe
    @property RecipeType type() const @safe
    {
        return RecipeType.dop;
    }

    @property bool isLight() const @safe
    {
        return false;
    }

    /// The package name
    @property string name() const @safe
    {
        return _name;
    }

    /// The package version
    @property Semver ver() const @safe
    {
        return _ver;
    }

    /// The package revision
    @property string revision() const @safe
    {
        return _rev;
    }

    @property void revision(string rev) @safe
    {
        _rev = rev;
    }

    @property string description() const @safe
    {
        return "Description of " ~ _name;
    }

    @property string upstreamUrl() const @safe
    {
        return "https://" ~ _name ~ ".test";
    }

    @property string license() const @safe
    {
        return "";
    }

    @property const(string)[] tools() const @safe
    {
        return _tools;
    }

    @property const(Option[string]) options() const @safe
    {
        return null;
    }

    /// Whether this recipe has dependencies.
    /// In case dependencies are only needed for some config cases, true is returned.
    @property bool hasDependencies() const @safe
    {
        return _deps.length != 0;
    }

    /// Get the dependencies of the package for the given build configuration
    const(DepSpec)[] dependencies(const(Profile) profile) @system
    {
        return _deps;
    }

    /// Get the files to include with the recipe when publishing to registry.
    /// This is relative to the root recipe dir.
    /// The current directory (as returned by `getcwd`) must be the
    /// recipe root directory
    string[] include() @system
    {
        return null;
    }

    /// Checks whether the source code is provided with the recipe.
    /// In this case, `source` may return a path relative to the recipe
    /// root directory
    @property bool inTreeSrc() const @safe
    {
        return true;
    }

    /// Ensure that the source is present and return
    /// the directory to the source root dir.
    /// In case of out-of-tree source code (the recipe packages a 3rd party code),
    /// The `source` function effectively download and prepare the source code.
    /// The current directory (as returned by `getcwd`) must be the
    /// recipe root directory
    string source() @system
    {
        return ".";
    }

    /// Build and install the package to the given directory and
    /// with provided config. Info about dependencies is also provided.
    /// The current directory (as returned by `getcwd`) must be the
    /// build directory (where to build object files or any intermediate file before installation).
    void build(BuildDirs dirs, const(BuildConfig) config, DepBuildInfo[string] depInfos = null) @system
    {
    }

    /// Whether this recipe can stage an installation to another
    /// directory without rebuilding from source.
    @property bool canStage() const @safe
    {
        return true;
    }

    /// Stage an installation to another directory.
    /// The current directory (as returned by `getcwd`) must be the
    /// recipe root directory.
    void stage(string src, string dest) @system
    {
        import dopamine.util;

        return installRecurse(src, dest);
    }

}
