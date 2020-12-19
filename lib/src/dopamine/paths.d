module dopamine.paths;

import dopamine.profile;
import dopamine.recipe;
import dopamine.util;

import std.file;
import std.format;
import std.path;

@safe:

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

string userLoginFile()
{
    return buildPath(userDopDir(), "login.json");
}

struct PackageDir
{
    private string _dir;

    @property string dir() const
    {
        return _dir;
    }

    @property bool exists() const
    {
        import std.file : exists, isDir;

        return exists(dir) && isDir(dir);
    }

    @property bool hasDopamineFile() const
    {
        import std.file : exists, isFile;

        const df = _path("dopamine.lua");
        return exists(df) && isFile(df);
    }

    @property string dopamineFile() const
    in(hasDopamineFile)
    {
        return _path("dopamine.lua");
    }

    @property string dopDir() const
    in(hasDopamineFile)
    {
        return _path(".dop");
    }

    @property string sourceDest() const
    in(hasDopamineFile)
    {
        return _path(".dop", "source");
    }

    @property FlagFile sourceFlag() const
    in(hasDopamineFile)
    {
        return FlagFile(_path(".dop", ".source"));
    }

    @property string profileFile() const
    in(hasDopamineFile)
    {
        return _path(".dop", "profile.ini");
    }

    ProfileDirs profileDirs(const(Profile) profile) const @trusted
    in(profile && hasDopamineFile)
    {
        const workDir = _workDirName(profile);

        ProfileDirs dirs = void;
        dirs.work = _path(".dop", workDir);
        dirs.build = _path(".dop", workDir, "build");
        dirs.install = _path(".dop", workDir, "install");
        return dirs;
    }

    /// Get the path to the packed archive
    /// Must be called from the package dir
    string archiveFile(const(Profile) profile, const(Recipe) recipe) const
    in(profile && recipe && hasDopamineFile)
    {
        import dopamine.archive : ArchiveBackend;

        import std.algorithm : findAmong;
        import std.exception : enforce;
        import std.format : format;

        const supportedFormats = ArchiveBackend.get.supportedExts;
        const preferredFormats = [".tar.xz", ".tar.bz2", ".tar.gz"];

        const archiveFormat = findAmong(preferredFormats, supportedFormats);

        enforce(archiveFormat.length, "No archive capability");

        const workDir = _workDirName(profile);
        const filename = format("%s-%s.%s%s", recipe.name, recipe.ver,
                profile.digestHash[0 .. 10], archiveFormat[0]);
        return _path(".dop", workDir, filename);
    }

    static PackageDir enforced(string dir, lazy string msg = null)
    {
        import std.exception : enforce;

        const pdir = PackageDir(dir);
        enforce(pdir.hasDopamineFile, msg.length ? msg
                : format("%s is not a Dopamine package directory", pdir.dir));
        return pdir;
    }

    private string _path(Args...)(Args comps) const @trusted
    {
        import std.array : array;
        import std.exception : assumeUnique;

        return assumeUnique(asNormalizedPath(chainPath(dir, comps)).array);
    }

    private static string _workDirName(const(Profile) profile)
    {
        return format("%s-%s", profile.digestHash[0 .. 10], profile.name);
    }
}

/// Structure gathering directories needed during a build
struct ProfileDirs
{
    /// dop working directory
    string work;
    /// directory into which build happens
    string build;
    /// directory into which files are installed
    string install;

    /// FlagFile that indicates that configuration is done
    FlagFile configFlag() const
    {
        return FlagFile(buildPath(work, ".config-ok"));
    }

    /// FlagFile that indicates that build is done
    FlagFile buildFlag() const
    {
        return FlagFile(buildPath(work, ".build-ok"));
    }

    /// FlagFile that indicates that install is done
    FlagFile installFlag() const
    {
        return FlagFile(buildPath(work, ".install-ok"));
    }
}
