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

string userProfileFile(Profile profile)
{
    return userProfileFile(profile.name);
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

/// Structure gathering directories needed during a build
struct ProfileDirs
{
    // dop working directory
    string work;
    // directory into which build happens
    string build;
    // directory into which files are installed
    string install;
}

/// Get the paths to the local profile
ProfileDirs localProfileDirs(Profile profile)
{
    import std.format : format;

    ProfileDirs dirs = void;
    dirs.work = buildPath(localDopDir, format("%s-%s", profile.digestHash[0 .. 10], profile.name));
    dirs.build = buildPath(dirs.work, "build");
    dirs.install = buildPath(dirs.work, "install");
    return dirs;
}

/// Get the path to the packed archive
/// Must be called from the package dir
string localPackageArchiveFile(ProfileDirs dirs, Recipe recipe)
in(recipe)
{
    import std.format : format;

    const filename = format("%s-%s%s", recipe.name, recipe.ver, ArchiveBackend.archiveExt);
    return buildPath(dirs.work, filename);
}
