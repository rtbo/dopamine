module dopamine.build;

import dopamine.profile;
import dopamine.util;

import std.array;
import std.exception;
import std.file;
import std.format;
import std.stdio;

enum BuildId
{
    meson,
}

interface BuildSystem
{
    BuildId id();
    void configure(string srcDir, string buildDir, string installDir, Profile profile);
    void build();
    void install();
}

class MesonBuildSystem : BuildSystem
{
    private string _meson;
    private string _ninja;

    private string _srcDir;
    private string _buildDir;
    private string _installDir;
    private Profile _profile;

    this()
    {
        _meson = findProgram("meson");
        _ninja = findProgram("ninja");

        if (!_meson || !_ninja)
        {
            throw new Exception("Meson backend needs meson and ninja on the system");
        }
    }

    override BuildId id()
    {
        return BuildId.meson;
    }

    override void configure(string srcDir, string buildDir, string installDir, Profile profile)
    {
        import std.path : asAbsolutePath, asRelativePath;
        import std.uni : toLower;

        if (_srcDir || _buildDir || _installDir || _profile)
        {
            stderr.writeln("Warning: Package already configured");
        }

        _srcDir = srcDir;
        _buildDir = asAbsolutePath(buildDir).asRelativePath(srcDir).array;
        _installDir = asAbsolutePath(installDir).array;
        _profile = profile;

        string[string] env;
        profile.collectEnvironment(env);

        runCommand([
                _meson, "setup", _buildDir, format("--prefix=%s", _installDir),
                format("--buildtype=%s", _profile.buildType.to!string.toLower),
                ], _srcDir, false, env);
    }

    override void build()
    {
        enforce(_srcDir && _buildDir && _installDir && _profile,
                "cannot build a project that is not configured");
        runCommand([_ninja], _buildDir);
    }

    override void install()
    {
        enforce(_srcDir && _buildDir && _installDir && _profile,
                "cannot install a project that is not configured");
        runCommand([_ninja, "install"], _buildDir);
    }
}
