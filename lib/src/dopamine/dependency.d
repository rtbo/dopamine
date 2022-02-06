module dopamine.dependency;

import dopamine.depspec;
import dopamine.semver;
import dopamine.recipe;

import std.format : format;
import std.typecons : Flag;

/// How a dependency is resolved
enum Resolution
{
    /// Dependency is not resolved
    none,
    /// Dependency is resolved with a recipe (either cached or downloaded)
    recipe,
    /// Dependency is resolved from the user system
    system,
}

/// A dependency that has a spec and can be resolved, either on system or from cache
class Dependency
{
    private string _name;
    private VersionSpec _spec;

    private Semver _resolvedVersion;
    private Recipe _resolvedRecipe;

    this(string name, VersionSpec spec)
    {
        _name = name;
        _spec = spec;
    }

    @property string name() const
    {
        return _name;
    }

    @property VersionSpec spec() const
    {
        return _spec;
    }

    @property bool resolved() const
    {
        return cast(bool)_resolvedVersion;
    }

    @property Resolution resolution() const
    {
        if (!_resolvedVersion)
        {
            return Resolution.none;
        }
        if (_resolvedRecipe)
        {
            return Resolution.recipe;
        }
        return Resolution.system;
    }

    @property Semver resolvedVersion() const
    {
        return _resolvedVersion;
    }

    @property inout(Recipe) resolvedRecipe() inout
    {
        return _resolvedRecipe;
    }

    void setResolvedSystem(Semver resolvedVersion)
    {
        setResolvedVersion(resolvedVersion);
    }

    void setResolvedRecipe(Recipe recipe)
    in (!resolved, format("Dependency %s is already resolved", _name))
    in (recipe && recipe.name == _name, format(
            "Recipe do not match dependency name: %s != %s", recipe.name, _name))
    {
        _resolvedRecipe = recipe;
        setResolvedVersion(recipe.ver);
    }

    private void setResolvedVersion(Semver resolvedVersion)
    in (!resolved, format("Dependency %s is already resolved", _name))
    in (_spec.matchVersion(resolvedVersion), format(
            "Dependency %s is resolved with unmatched version: %s doesn't allow %s", _name, _spec, resolvedVersion))
    {
        _resolvedVersion = resolvedVersion;
    }
}
