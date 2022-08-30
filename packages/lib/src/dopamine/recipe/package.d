module dopamine.recipe;

import dopamine.dep.spec;
import dopamine.profile;
import dopamine.semver;

import std.file;
import std.path;
import std.sumtype;

public import dopamine.recipe.dir;
public import dopamine.recipe.dop;

/// A recipe dependency specification
struct DepSpec
{
    string name;
    VersionSpec spec;
    bool dub;
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

alias OptionVal = SumType!(bool, string, int);

struct Option
{
    OptionVal defaultValue;
    string description;
}

/// The build configuration
struct BuildConfig
{
    /// the build profile
    const(Profile) profile;

    // TODO: options

    void feedDigest(D)(ref D digest) const
    {
        profile.feedDigest(digest);
    }
}

struct DepInfo
{
    string installDir;
    Semver ver;
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
    void build(BuildDirs dirs, BuildConfig config, DepInfo[string] depInfos = null) @system
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
    void build(BuildDirs dirs, BuildConfig config, DepInfo[string] depInfos = null) @system
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
