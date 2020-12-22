module dopamine.build;

import dopamine.log;
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

    static bool configureNeeded(PackageDir packageDir, const(Profile) profile)
    {
        import dopamine.source : Source;

        assert(!Source.fetchNeeded(packageDir));

        const dirs = packageDir.profileDirs(profile);
        auto flagFile = dirs.configFlag(); // @suppress(dscanner.suspicious.unmodified)
        if (!flagFile.exists)
            return true;

        auto srcFf = packageDir.sourceFlag();

        const lastMtime = flagFile.timeLastModified;

        return lastMtime < srcFf.timeLastModified
            || lastMtime < timeLastModified(packageDir.dopamineFile());
    }

    static bool buildNeeded(PackageDir packageDir, const(Profile) profile)
    {
        import dopamine.source : Source;

        assert(!configureNeeded(packageDir, profile));

        const dirs = packageDir.profileDirs(profile);
        auto flagFile = dirs.buildFlag(); // @suppress(dscanner.suspicious.unmodified)
        if (!flagFile.exists)
            return true;

        auto confFf = dirs.configFlag();

        const lastMtime = flagFile.timeLastModified;

        return lastMtime < confFf.timeLastModified
            || lastMtime < timeLastModified(packageDir.dopamineFile());
    }

    static bool installNeeded(PackageDir packageDir, const(Profile) profile)
    {
        import dopamine.source : Source;

        assert(!buildNeeded(packageDir, profile));

        const dirs = packageDir.profileDirs(profile);
        auto flagFile = dirs.installFlag(); // @suppress(dscanner.suspicious.unmodified)
        if (!flagFile.exists)
            return true;

        auto buildFf = dirs.buildFlag();

        const lastMtime = flagFile.timeLastModified;

        return lastMtime < buildFf.timeLastModified
            || lastMtime < timeLastModified(packageDir.dopamineFile());
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

        auto flagFile = dirs.buildFlag();
        scope (success)
            flagFile.write();
        scope (failure)
            flagFile.remove();

        runCommand([_ninja], dirs.build);
    }

    override void install(ProfileDirs dirs) const
    {
        auto flagFile = dirs.installFlag();
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

        auto flagFile = dirs.configFlag();

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
                ], dirs.build, LogLevel.verbose, env);
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

        auto flagFile = dirs.configFlag();
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
                ], srcDir, LogLevel.verbose, env);
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
