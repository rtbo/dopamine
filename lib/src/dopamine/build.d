module dopamine.build;

import dopamine.paths;
import dopamine.profile;
import dopamine.util;

import std.array;
import std.exception;
import std.file;
import std.format;
import std.json;
import std.path;
import std.stdio;

@safe:

interface BuildSystem
{
    string name() const;
    void configure(string srcDir, ProfileDirs dirs, Profile profile) const;
    void build(ProfileDirs dirs) const;
    void install(ProfileDirs dirs) const;

    final bool configured(ProfileDirs dirs) const
    {
        return exists(configuredFlagPath(dirs));
    }

    JSONValue toJson() const;
}

abstract class NinjaBuildSystem : BuildSystem
{
    private string _ninja;

    this()
    {
        _ninja = enforce(findProgram("ninja"), "ninja must be installed on the system");
    }

    abstract override string name() const;
    abstract override void configure(string srcDir, ProfileDirs dirs, Profile profile) const;

    override void build(ProfileDirs dirs) const
    {
        enforce(configured(dirs), "cannot build a package that is not configured");
        runCommand([_ninja], dirs.build);
    }

    override void install(ProfileDirs dirs) const
    {
        enforce(configured(dirs), "cannot install a package that is not configured");
        runCommand([_ninja, "install"], dirs.build);
    }

    abstract override JSONValue toJson() const;
}

class CMakeBuildSystem : NinjaBuildSystem
{
    private string _cmake;

    this()
    {
        _cmake = enforce(findProgram("cmake"), "cmake must be installed on the system");
    }

    override string name() const
    {
        return "CMake";
    }

    override void configure(string srcDir, ProfileDirs dirs, Profile profile) const @trusted
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

        const installDir = asAbsolutePath(dirs.install).array;
        srcDir = assumeUnique(asAbsolutePath(srcDir).asRelativePath(dirs.build).array);

        mkdirRecurse(dirs.build);

        string[string] env;
        profile.collectEnvironment(env);

        runCommand([
                _cmake, "-G", "Ninja",
                format("-DCMAKE_INSTALL_PREFIX=%s", installDir),
                format("-DCMAKE_BUILD_TYPE=%s", profile.buildType.to!string),
                srcDir
                ], dirs.build, false, env);
    }

    override JSONValue toJson() const
    {
        import std.conv : to;

        JSONValue json;
        json["type"] = "build";
        json["method"] = "cmake";
        return json;
    }

}

class MesonBuildSystem : NinjaBuildSystem
{
    private string _meson;
    private string _ninja;

    this()
    {
        _meson = enforce(findProgram("meson"), "meson must be installed on the system");
    }

    override string name() const
    {
        return "Meson";
    }

    override void configure(string srcDir, ProfileDirs dirs, Profile profile) const @trusted
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

    override JSONValue toJson() const
    {
        import std.conv : to;

        JSONValue json;
        json["type"] = "build";
        json["method"] = "meson";
        return json;
    }
}

private string configuredFlagPath(ProfileDirs dirs)
{
    return buildPath(dirs.work, "configured-ok");
}

private void writeConfiguredFlag(ProfileDirs dirs)
{
    import std.file : write;

    mkdirRecurse(dirs.work);
    write(configuredFlagPath(dirs), "");
}

private void removeConfiguredFlag(ProfileDirs dirs)
{
    const cfp = configuredFlagPath(dirs);
    if (exists(cfp))
        remove(cfp);
}
