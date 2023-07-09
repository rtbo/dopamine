module dopamine.recipe;

import dopamine.build_id;
import dopamine.dep.spec;
import dopamine.profile;
import dopamine.semver;

import std.file;
import std.json;
import std.path;
import std.string;
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

    static OptionSet fromJson(JSONValue json) @trusted
    {
        import std.conv : to;

        if (json.type == JSONType.null_)
            return OptionSet.init;

        OptionVal[string] opts;

        foreach (string key, const ref JSONValue val; json.objectNoRef)
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
                throw new Exception("Invalid JSON option type: " ~ val.type.to!string);
            }
        }

        return OptionSet(opts);
    }

    JSONValue toJson() const @safe
    {
        import std.sumtype : match;

        if (!_opts.length)
            return JSONValue.init;

        JSONValue[string] json;

        foreach (name, opt; _opts)
        {
            opt.match!(
                (bool val) => json[name] = val,
                (int val) => json[name] = val,
                (string val) => json[name] = val,
            );
        }

        return JSONValue(json);
    }

    bool opCast(T : bool)() const @safe
    {
        return _opts.length > 0;
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

struct PackageName
{
    string name;

    alias name this;

    @property bool isModule() const pure @safe
    {
        return name.indexOf(':') != -1;
    }

    @property string pkgName() const pure @safe
    {
        const colon = name.indexOf(':');
        if (colon == -1)
            return name;
        else
            return name[0 .. colon];
    }

    @property string modName() const pure @safe
    {
        const colon = name.indexOf(':');
        if (colon == -1)
            return null;
        else
            return name[colon + 1 .. $];
    }

    string toString() const pure @safe
    {
        return name;
    }
}

/// A provider of dependency
enum DepProvider
{
    dop,
    dub,
}

@property bool isDop(DepProvider provider) @safe
{
    return provider == DepProvider.dop;
}

@property bool isDub(DepProvider provider) @safe
{
    return provider == DepProvider.dub;
}

/// A recipe dependency specification
struct DepSpec
{
    import std.typecons;

    PackageName name;
    VersionSpec spec;
    DepProvider provider;
    OptionSet options;

    this(string name, VersionSpec spec, DepProvider provider = DepProvider.dop, OptionSet options = OptionSet
            .init) @safe
    {
        this.name = PackageName(name);
        this.spec = spec;
        this.provider = provider;
        this.options = options;
    }

    @property DepSpec dup() const @safe
    {
        return DepSpec(name, spec, provider, options.dup);
    }

    /// If this spec is for a module, return the spec to the super package.
    /// Otherwise, return this.
    @property const(DepSpec) pkgSpec() const @safe
    {
        if (name.isModule)
            return DepSpec(PackageName(name.pkgName), spec, provider, options.dup);
        else
            return this;
    }

    static DepSpec fromJson(JSONValue json) @safe
    {
        import std.conv : to;

        auto jdep = json.objectNoRef;
        OptionSet options;
        if (auto jo = "options" in jdep)
            options = OptionSet.fromJson(*jo);

        return DepSpec(
            jdep["name"].str,
            VersionSpec(jdep["spec"].str),
        jdep["provider"].str.to!DepProvider,
        options
        );
    }

    /// Serialize to JSON.
    /// Name is not included because the returned JSON value is typically stored
    /// in a dict for which the key is the dependency name.
    JSONValue toJson() const @safe
    {
        import std.conv : to;

        JSONValue[string] json;
        json["name"] = name.toString();
        json["spec"] = spec.toString();
        json["provider"] = provider.to!string;
        if (options)
            json["options"] = options.toJson();

        return JSONValue(json);
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

/// Configuration for dependency resolution
struct ResolveConfig
{
    HostInfo hostInfo;
    BuildType buildType;
    const(string)[] modules;
    OptionSet options;

    this(HostInfo hostInfo, BuildType buildType, const(string)[] modules, OptionSet options) @safe
    {
        this.hostInfo = hostInfo;
        this.buildType = buildType;
        this.modules = modules;
        this.options = options;
    }

    this(const(Profile) profile, const(string)[] modules, OptionSet options) @safe
    {
        this.hostInfo = profile.hostInfo;
        this.buildType = profile.buildType;
        this.modules = modules;
        this.options = options;
    }

    static ResolveConfig fromJson(JSONValue json) @safe
    {
        import std.algorithm : map;
        import std.array : array;

        const arch = fromConfig!Arch(json["arch"].str);
        const os = fromConfig!OS(json["os"].str);
        const buildType = fromConfig!BuildType(json["buildType"].str);
        const modules = json["modules"].arrayNoRef.map!(j => j.str).array;
        auto options = OptionSet.fromJson(json["options"]);

        return ResolveConfig(HostInfo(arch, os), buildType, modules, options);
    }

    JSONValue toJson() const @safe
    {
        import std.algorithm : map;
        import std.array : array;

        JSONValue[string] json;
        json["arch"] = this.hostInfo.arch.toConfig;
        json["os"] = this.hostInfo.os.toConfig;
        json["buildType"] = this.buildType.toConfig;
        json["modules"] = this.modules.map!(m => JSONValue(m)).array;
        json["options"] = this.options.toJson();

        return JSONValue(json);
    }
}

/// The build configuration
struct BuildConfig
{
    /// the build profile
    const(Profile) profile;

    /// The modules to build
    const(string)[] modules;

    /// The build options
    OptionSet options;

    this(const(Profile) profile)
    {
        this.profile = profile;
    }

    this(const(Profile) profile, const(string)[] modules)
    {
        this.profile = profile;
        this.modules = modules;
    }

    this(const(Profile) profile, OptionSet options)
    {
        this.profile = profile;
        this.options = options;
    }

    this(const(Profile) profile, const(string)[] modules, OptionSet options)
    {
        this.profile = profile;
        this.modules = modules;
        this.options = options;
    }

    void feedDigest(D)(ref D digest) const
    {
        import dopamine.util : feedDigestData;
        import std.algorithm : sort;
        import std.sumtype : match;

        profile.feedDigest(digest);

        foreach (mod; modules)
            feedDigestData(digest, mod);

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
    /// The provider of dependency (whether it is a Dopamine or DUB dependency)
    DepProvider provider;
    /// The version of the dependency package
    Semver ver;
    /// The build-id of the dependency package
    BuildId buildId;
    /// Where the dependency is install
    string installDir;
}

/// A struct that hold the build info for a complete dependency graph.
/// As there can be name collisions between different dependency providers
/// in the same graph, there is one map per provider.
struct DepGraphBuildInfo
{
    /// Build-info of regular (aka. dopamine) packages
    DepBuildInfo[string] dop;
    /// Build-info of DUB packages
    DepBuildInfo[string] dub;

    bool opCast(T: bool)() const
    {
        return dop.length > 0 || dub.length > 0;
    }

    DepBuildInfo[string] opIndex(DepProvider provider)
    {
        final switch (provider)
        {
        case DepProvider.dop:
            return dop;
        case DepProvider.dub:
            return dub;
        }
    }

    DepBuildInfo opIndexAssign(DepBuildInfo value, DepProvider provider, string name)
    {
        final switch (provider)
        {
        case DepProvider.dop:
            return dop[name] = value;
        case DepProvider.dub:
            return dub[name] = value;
        }
    }

    DepBuildInfo opIndex(DepProvider provider, string name)
    {
        return opIndex(provider)[name];
    }


}

enum RecipeType
{
    /// A genuine dopamine recipe
    dop,
    /// A recipe for Dub
    dub,
}

@property DepProvider toDepProvider(RecipeType type) @safe
{
    // not sure a one to one map will last forever
    final switch (type)
    {
    case RecipeType.dop:
        return DepProvider.dop;
    case RecipeType.dub:
        return DepProvider.dub;
    }
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
    /// In case dependencies are only needed for some profile cases, true is returned.
    @property bool hasDependencies() const @safe;

    /// Whether the dependencies of this recipe depend on the resolution configuration (`ResolveConfig`).
    @property bool hasDynDependencies() const @safe;

    /// Get the dependencies of the package for the given configuration.
    const(DepSpec)[] dependencies(const(ResolveConfig) config) @system;

    /// Whether this recipe has dependencies.
    /// In case dependencies are only needed for some profile cases, true is returned.
    final @property bool hasModules() @safe
    {
        return modules.length != 0;
    }

    /// Get the list of modules declared by this recipe
    @property string[] modules() @safe;

    /// Get the dependencies of the provided module for the given configuration
    @property const(DepSpec)[] moduleDependencies(string moduleName, const(ResolveConfig) config) @system;

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

    /// Return the source path of a module (relative to root)
    /// This value is passed in the `dirs` argument of `buildModule`
    string moduleSourceDir(string modName) @safe;

    /// Whether this recipe expects modules to be built by batch or one-by-one.
    /// Batch building means that the they are built by the main `build` function.
    /// Otherwise they are be built by the `buildModule` function.
    @property bool modulesBatchBuild() @safe;

    /// Build one module of this recipe.
    /// The module is specified as unique member of config.modules
    void buildModule(BuildDirs dirs, const(BuildConfig) config, DepGraphBuildInfo depInfos) @system
    in (config.modules.length == 1);

    /// Build and install the package to the given directory and
    /// with provided config. Info about dependencies is also provided.
    /// The current directory (as returned by `getcwd`) must be the
    /// build directory (where to build object files or any intermediate file before installation).
    void build(BuildDirs dirs, const(BuildConfig) config, DepGraphBuildInfo depInfos) @system
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

// dfmt off
version (unittest):
// dfmt on

final class MockRecipe : Recipe
{
    private string _name;
    private Semver _ver;
    private RecipeType _type;
    private string _rev;
    private DepSpec[] _deps;
    private string[] _tools;

    this(string name, Semver ver, RecipeType type, string rev, DepSpec[] deps, string[] tools) @safe
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

    @property bool hasDynDependencies() const @safe
    {
        return false;
    }

    /// Get the dependencies of the package for the given configuration
    const(DepSpec)[] dependencies(const(ResolveConfig) config) @system
    {
        return _deps;
    }

    /// modules not supported yet
    @property string[] modules() @safe
    {
        return [];
    }
    /// ditto
    @property const(DepSpec)[] moduleDependencies(string moduleName, const(ResolveConfig) config) @system
    {
        return [];
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

    string moduleSourceDir(string modName) @safe
    {
        return ".";
    }

    @property bool modulesBatchBuild() @safe
    {
        return true;
    }

    void buildModule(BuildDirs dirs, const(BuildConfig) config, DepGraphBuildInfo depInfos) @system
    {
    }

    /// Build and install the package to the given directory and
    /// with provided config. Info about dependencies is also provided.
    /// The current directory (as returned by `getcwd`) must be the
    /// build directory (where to build object files or any intermediate file before installation).
    void build(BuildDirs dirs, const(BuildConfig) config, DepGraphBuildInfo depInfos) @system
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
