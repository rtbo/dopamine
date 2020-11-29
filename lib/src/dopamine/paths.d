module dopamine.paths;

import dopamine.pack;
import dopamine.profile;
import dopamine.recipe;

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

/// Check if current working directory is a package directory.
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
/// Must be called from package dir.
string localDopDir()
in(inPackageDefinitionDir())
{
    return ".dop";
}

/// Get the local profile file
string localProfileFile()
{
    return buildPath(localDopDir, "profile.ini");
}

/// Get the working dir for the selected profile
/// Must be called from the package dir
string localProfileWorkDir(Profile profile)
in(profile && inPackageDefinitionDir())
{
    import std.format : format;

    return buildPath(localDopDir, format("%s-%s", profile.digestHash[0 .. 10],
            profile.name));
}

/// Get the build dir for the selected profile
/// Must be called from the package dir
string localBuildDir(Profile profile)
in(profile && inPackageDefinitionDir())
{
    import std.format : format;

    return buildPath(localProfileWorkDir(profile), "build");
}

/// Get the install dir for the selected profile
/// Must be called from the package dir
string localInstallDir(Profile profile)
in(profile && inPackageDefinitionDir())
{
    import std.format : format;

    return buildPath(localProfileWorkDir(profile), "install");
}

/// Get the path to the packed archive
/// Must be called from the package dir
string localPackageArchiveFile(Profile profile, Recipe recipe)
in(profile && recipe && inPackageDefinitionDir())
{
    import std.format : format;

    const filename = format("%s-%s%s", recipe.name, recipe.ver, ArchiveBackend.archiveExt);
    return buildPath(localProfileWorkDir(profile), filename);
}