module dopamine.paths;

import std.path;

string userDopDir()
{
    import std.process : environment;

    version (linux)
    {
        return buildPath(environment["HOME"], ".dopamine");
    }
    else version (Windows)
    {
        return buildPath(environment["LOCALAPPDATA"], "Dopamine");
    }
    else
    {
        static assert(false, "unsupported OS");
    }
}

string userProfileDir()
{
    return buildPath(userDopDir(), "profiles");
}

string userProfileFile(string name)
{
    return buildPath(userProfileDir(), name ~ ".ini");
}

/// Check if current working directory is a package definition directory.
/// This is defined as a directory containing a `dopamine.lua` file
bool inPackageDefinitionDir()
{
    import std.file : exists;

    return exists("dopamine.lua");
}

/// Enforces that cwd is in a package directory.
void enforcePackageDefinitionDir()
{
    import std.exception : enforce;

    enforce(inPackageDefinitionDir(),
            "Out of package definition directory (containing dopamine.lua file)");
}

/// Get the local dopamine folder
/// Only valid within a directory containing `dopamine.lua`
string localDopDir()
in(inPackageDefinitionDir())
{
    return ".dop";
}

/// Get the local profile file
string localProfileFile()
in(inPackageDefinitionDir())
{
    return buildPath(".dop", "profile.ini");
}
