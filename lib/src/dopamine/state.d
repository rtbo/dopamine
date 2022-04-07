module dopamine.state;

import dopamine.paths;
import dopamine.recipe;
import dopamine.util;

/// Content of the main state for the package dir state
struct PkgState
{
    string srcDir;
}

alias PkgStateFile = JsonStateFile!PkgState;

@property PkgStateFile stateFile(const RecipeDir rdir)
{
    return PkgStateFile(rdir._dopPath("state.json"));
}


string checkSourceReady(RecipeDir dir, Recipe recipe, out string reason)
{
    if (recipe.inTreeSrc)
    {
        const srcDir = recipe.source();
        return srcDir;
    }

    auto sf = dir.stateFile;
    auto state = sf.read();
    if (!sf || !state.srcDir)
    {
        reason = "Source directory is not ready";
        return null;
    }

    if (sf.timeLastModified < dir.recipeLastModified)
    {
        reason = "Source directory is not up-to-date";
        return null;
    }
    return state.srcDir;
}

/// Content of the state relative to a build configuration
struct ConfigState
{
    import std.datetime : SysTime;

    SysTime buildTime;

    bool opCast(T : bool)() const
    {
        return !!buildDir;
    }
}

alias ConfigStateFile = JsonStateFile!ConfigState;

@property ConfigStateFile stateFile(const ConfigDirs cdirs)
{
    return ConfigStateFile(cdirs.statePath);
}

bool checkBuildReady(RecipeDir rdir, ConfigDirs cdirs, out string reason)
{
    import std.file : exists;

    if (!exists(cdirs.installDir))
    {
        reason = "Install directory doesn't exist";
        return false;
    }

    if (!cdirs.stateFile.exists())
    {
        reason = "Build config state file doesn't exist";
        return false;
    }

    const rtime = rdir.recipeLastModified;
    auto state = cdirs.stateFile.read();

    if (rtime >= cdirs.stateFile.timeLastModified ||
        rtime >= state.buildTime)
    {
        reason = "Build is not up-to-date";
        return false;
    }

    return true;
}
