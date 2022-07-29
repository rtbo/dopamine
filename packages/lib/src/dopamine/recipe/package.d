module dopamine.recipe;

import dopamine.dep.spec;
import dopamine.profile;
import dopamine.semver;

import std.file;
import std.path;

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
}

enum RecipeType
{
    /// Package recipe is a full package
    /// that has source code and build process.
    pack,
    /// Light recipe is a recipe that only defines dependencies.
    /// It is meant for dopamine to stage all necessary dependencies
    /// an application needs, without the need to publish a build recipe.
    light,
}

interface Recipe
{
    /// The type of recipe
    @property RecipeType type() const @safe;

    /// Helper for the recipe type
    final @property bool isPackage() const @safe
    {
        return type == RecipeType.pack;
    }

    /// ditto
    final @property bool isLight() const @safe
    {
        return type == RecipeType.light;
    }

    /// The package name
    @property string name() const @safe;

    /// The package version
    @property Semver ver() const @safe;

    /// The package revision
    @property string revision() const @safe;
    @property void revision(string rev) @safe;

    // FIXME: change "langs" to "tools" with possibility of arbitrary tools
    /// Return languages present in this recipe.
    /// This will determine the toolchain needed to build the package.
    @property const(Lang)[] langs() const @safe;

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
    in (isPackage, "Light recipes have no defined source");

    /// Build and install the package to the given directory and
    /// with provided config. Info about dependencies is also provided.
    /// The current directory (as returned by `getcwd`) must be the
    /// build directory (where to build object files or any intermediate file before installation).
    void build(BuildDirs dirs, BuildConfig config, DepInfo[string] depInfos = null) @system
    in (isPackage, "Light recipes do not build");

    /// Whether this recipe can stage an installation to another
    /// directory without rebuilding from source.
    @property bool canStage() const @safe;

    /// Stage an installation to another directory.
    /// The current directory (as returned by `getcwd`) must be the
    /// recipe root directory.
    void stage(string src, string dest) @system
    in (isPackage, "Light recipes do not stage")
    in (canStage, "Recipe can't stage");
}

version (unittest)  : final class MockRecipe : Recipe
{
    private string _name;
    private Semver _ver;
    private string _rev;
    private DepSpec[] _deps;
    private Lang[] _langs;

    this(string name, Semver ver, string rev, DepSpec[] deps, Lang[] langs)
    {
        _name = name;
        _ver = ver;
        _rev = rev;
        _deps = deps;
        _langs = langs;
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
        return RecipeType.pack;
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

    // FIXME: change "langs" to "tools" with possibility of arbitrary tools
    /// Return languages present in this recipe.
    /// This will determine the toolchain needed to build the package.
    @property const(Lang)[] langs() const @safe
    {
        return _langs;
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
    in (isPackage, "Light recipes have no defined source")
    {
        return ".";
    }

    /// Build and install the package to the given directory and
    /// with provided config. Info about dependencies is also provided.
    /// The current directory (as returned by `getcwd`) must be the
    /// build directory (where to build object files or any intermediate file before installation).
    void build(BuildDirs dirs, BuildConfig config, DepInfo[string] depInfos = null) @system
    in (isPackage, "Light recipes do not build")
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
    in (isPackage, "Light recipes do not stage")
    in (canStage, "Recipe can't stage")
    {
        import dopamine.util;

        return installRecurse(src, dest);
    }

}
