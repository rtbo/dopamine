module dopamine.state;

import dopamine.paths;
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

@property ConfigStateFile stateFile(const ConfigDir cdir)
{
    return ConfigStateFile(cdir.dir ~ ".json");
}
