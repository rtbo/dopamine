module dopamine.state;

import dopamine.recipe;
import dopamine.util;

/// Content of the main state for the package dir state
struct PkgState
{
    string srcDir;
}

alias PkgStateFile = JsonStateFile!PkgState;

@property PkgStateFile stateFile(RecipeDir rdir)
{
    return PkgStateFile(rdir.dopPath("state.json"));
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

@property BuildStateFile stateFile(const BuildPaths bPaths)
{
    return BuildStateFile(bPaths.state);
}

bool checkBuildReady(RecipeDir rdir, BuildPaths bPaths, out string reason)
{
    import std.file : exists;

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

    const rtime = rdir.recipeLastModified;
    auto state = bPaths.stateFile.read();

    if (rtime >= bPaths.stateFile.timeLastModified ||
        rtime >= state.buildTime)
    {
        reason = "Build is not up-to-date";
        return false;
    }

    return true;
}
