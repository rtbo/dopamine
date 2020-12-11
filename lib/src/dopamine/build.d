module dopamine.build;

import dopamine.paths;
import dopamine.profile;
import dopamine.util;

import std.array;
import std.exception;
import std.file;
import std.format;
import std.path;
import std.stdio;

@safe:

interface BuildSystem
{
    string name();
    void configure(string srcDir, ProfileDirs dirs, Profile profile);
    void build(ProfileDirs dirs);
    void install(ProfileDirs dirs);

    final bool configured(ProfileDirs dirs)
    {
        return exists(configuredFlagPath(dirs));
    }
}

class MesonBuildSystem : BuildSystem
{
    private string _meson;
    private string _ninja;

    this()
    {
        _meson = findProgram("meson");
        _ninja = findProgram("ninja");

        if (!_meson || !_ninja)
        {
            throw new Exception("Meson backend needs meson and ninja on the system");
        }
    }

    override string name()
    {
        return "meson";
    }

    override void configure(string srcDir, ProfileDirs dirs, Profile profile) @trusted
    {
        import std.path : asAbsolutePath, asRelativePath;
        import std.uni : toLower;

        if (configured(dirs))
        {
            stderr.writeln("Warning: Package already configured, reconfiguring...");
        }

        scope (success)
            writeConfiguredFlag(dirs);
        scope (failure)
            removeConfiguredFlag(dirs);

        const buildDir = assumeUnique(asAbsolutePath(dirs.build).asRelativePath(srcDir).array);
        const installDir = asAbsolutePath(dirs.install).array;

        string[string] env;
        profile.collectEnvironment(env);

        runCommand([
                _meson, "setup", buildDir, format("--prefix=%s", installDir),
                format("--buildtype=%s", profile.buildType.to!string.toLower),
                ], srcDir, false, env);
    }

    override void build(ProfileDirs dirs)
    {
        enforce(configured(dirs), "cannot build a package that is not configured");
        runCommand([_ninja], dirs.build);
    }

    override void install(ProfileDirs dirs)
    {
        enforce(configured(dirs), "cannot install a package that is not configured");
        runCommand([_ninja, "install"], dirs.build);
    }
}

private string configuredFlagPath(ProfileDirs dirs)
{
    return buildPath(dirs.work, ".priv", "configured-ok");
}

private void writeConfiguredFlag(ProfileDirs dirs)
{
    import std.file : write;

    mkdirRecurse(buildPath(dirs.work, ".priv"));
    write(configuredFlagPath(dirs), "");
}

private void removeConfiguredFlag(ProfileDirs dirs)
{
    remove(configuredFlagPath(dirs));
}
