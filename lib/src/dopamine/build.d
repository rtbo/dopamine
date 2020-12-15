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
    void configure(string srcDir, ProfileDirs dirs, const(Profile) profile) const;
    void build(ProfileDirs dirs) const;
    void install(ProfileDirs dirs) const;

    JSONValue toJson() const;

    static bool configureNeeded(string packageDir, const(Profile) profile)
    {
        import dopamine.source : sourceFlagFile, Source;

        assert(!Source.fetchNeeded(packageDir));

        const dirs = localProfileDirs(packageDir, profile);
        auto flagFile = configuredFlagFile(dirs); // @suppress(dscanner.suspicious.unmodified)
        if (!flagFile.exists)
            return true;

        auto srcFf = sourceFlagFile(packageDir);

        const lastMtime = flagFile.timeLastModified;

        return lastMtime < srcFf.timeLastModified
            || lastMtime < timeLastModified(localDopamineFile(packageDir));
    }

    static bool buildNeeded(string packageDir, const(Profile) profile)
    {
        import dopamine.source : sourceFlagFile, Source;

        assert(!configureNeeded(packageDir, profile));

        const dirs = localProfileDirs(packageDir, profile);
        auto flagFile = buildFlagFile(dirs); // @suppress(dscanner.suspicious.unmodified)
        if (!flagFile.exists)
            return true;

        auto confFf = configuredFlagFile(dirs);

        const lastMtime = flagFile.timeLastModified;

        return lastMtime < confFf.timeLastModified
            || lastMtime < timeLastModified(localDopamineFile(packageDir));
    }

    static bool installNeeded(string packageDir, const(Profile) profile)
    {
        import dopamine.source : sourceFlagFile, Source;

        assert(!buildNeeded(packageDir, profile));

        const dirs = localProfileDirs(packageDir, profile);
        auto flagFile = installFlagFile(dirs); // @suppress(dscanner.suspicious.unmodified)
        if (!flagFile.exists)
            return true;

        auto buildFf = buildFlagFile(dirs);

        const lastMtime = flagFile.timeLastModified;

        return lastMtime < buildFf.timeLastModified
            || lastMtime < timeLastModified(localDopamineFile(packageDir));
    }
}

abstract class NinjaBuildSystem : BuildSystem
{
    private string _ninja;

    this()
    {
        _ninja = enforce(findProgram("ninja"), "ninja must be installed on the system");
    }

    abstract override string name() const;
    abstract override void configure(string srcDir, ProfileDirs dirs, const(Profile) profile) const;

    override void build(ProfileDirs dirs) const
    {

        auto flagFile = buildFlagFile(dirs);
        scope (success)
            flagFile.write();
        scope (failure)
            flagFile.remove();

        runCommand([_ninja], dirs.build);
    }

    override void install(ProfileDirs dirs) const
    {
        auto flagFile = installFlagFile(dirs);
        scope (success)
            flagFile.write();
        scope (failure)
            flagFile.remove();

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

    override void configure(string srcDir, ProfileDirs dirs, const(Profile) profile) const @trusted
    {
        import std.path : asAbsolutePath, asRelativePath;
        import std.uni : toLower;

        auto flagFile = configuredFlagFile(dirs);

        scope (success)
            flagFile.write();
        scope (failure)
            flagFile.remove();

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

    override void configure(string srcDir, ProfileDirs dirs, const(Profile) profile) const @trusted
    {
        import std.path : asAbsolutePath, asRelativePath;
        import std.uni : toLower;

        auto flagFile = configuredFlagFile(dirs);
        scope (success)
            flagFile.write();
        scope (failure)
            flagFile.remove();

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

FlagFile configuredFlagFile(ProfileDirs dirs)
{
    return FlagFile(buildPath(dirs.work, "configure-ok"));
}

FlagFile buildFlagFile(ProfileDirs dirs)
{
    return FlagFile(buildPath(dirs.work, "build-ok"));
}

FlagFile installFlagFile(ProfileDirs dirs)
{
    return FlagFile(buildPath(dirs.work, "install-ok"));
}
