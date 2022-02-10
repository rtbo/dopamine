module dopamine.msvc;

// dfmt off
// version (Windows):
// dfmt on

import dopamine.log;
import dopamine.profile : Arch;
import dopamine.semver;
import dopamine.util;

import std.json;
import std.path;
import std.process;

struct VsVcInstall
{
    string installPath;
    string displayName;
    string productLineVersion; // 2017, 2019 ...
    Semver ver;

    @property string promptScript() const
    in (installPath.length > 0, "install path not set")
    {
        return buildPath(installPath, "Common7", "Tools", "VsDevCmd.bat");
    }

    bool opCast(T : bool)() const
    {
        return installPath.length > 0;
    }
}

private string vcArch(Arch arch)
{
    final switch (arch)
    {
    case Arch.x86_64:
        return "x64";
    case Arch.x86:
        return "x86";
    }
}

/// collect msvc environment by invoking a script that runs the prompt script and dumps environment to stdout
void collectEnvironment(const ref VsVcInstall install, ref string[string] env, Arch host,
        Arch target)
{
    import std.algorithm : canFind;
    import std.exception : enforce;
    import std.file : remove;
    import std.format : format;
    import std.stdio : File, stdin;
    import std.conv : to;

    logVerbose("Collecting %s %s environment for host %s and target %s", info("MSVC"),
            info(install.productLineVersion), info(host.to!string), info(target.to!string));

    const scriptPath = tempPath(null, "vcenv", ".bat");

    const invokeLine = format("call \"%s\" -arch=%s -host_arch=%s",
            install.promptScript, vcArch(target), vcArch(host));

    enum startMark = "__dopamine_start_mark__";
    enum endMark = "__dopamine_end_mark__";

    {
        auto script = File(scriptPath, "w");

        script.writeln("@echo off");
        script.writeln(invokeLine);
        script.writeln("echo " ~ startMark);
        script.writeln("set"); // dump environment variables
        script.writeln("echo " ~ endMark);
    }

    scope (exit)
        remove(scriptPath);

    auto p = pipe();
    auto childIn = stdin;
    auto childOut = p.writeEnd;
    auto childErr = File("NUL", "w");
    // Do not use retainStdout here as the output reading loop would hang forever.
    const config = Config.none;
    auto pid = spawnShell(scriptPath, childIn, childOut, childErr, null, config);
    bool withinMarks;
    foreach (l; p.readEnd.byLine)
    {
        if (!withinMarks && l.canFind(startMark))
        {
            withinMarks = true;
        }
        else if (withinMarks && l.canFind(endMark))
        {
            withinMarks = false;
        }
        else if (withinMarks)
        {
            import std.algorithm : findSplit;
            import std.string : strip;

            auto splt = l.strip().idup.findSplit("=");
            if (splt && environment.get(splt[0]) != splt[2])
            {
                env[splt[0]] = splt[2];
            }
        }
    }
    const exitCode = pid.wait();
    enforce(exitCode == 0, "detection of MSVC environment failed");
}

struct VsWhereResult
{
    bool hasVsWhere;
    VsVcInstall[] installs;

    bool opCast(T : bool)() const
    {
        return hasVsWhere;
    }
}

VsWhereResult runVsWhere()
{
    import std.algorithm : sort;
    import std.format : format;

    const vswhere = vswhereCmd();
    if (!vswhere)
        return VsWhereResult(false);

    // dfmt off
    const res = execute([
            vswhere, "-all", "-products", "*",
            "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "-utf8", "-format", "json"
            ]);
    // dfmt on

    if (res.status != 0)
        throw new Exception(format("vswhere.exe failed with exit code %s%s",
                res.status, res.output ? "\n" ~ res.output : ""));

    VsVcInstall[] installs;
    auto json = parseJSON(res.output);
    auto jInstalls = json.array;
    foreach (jv; jInstalls)
    {
        VsVcInstall install;
        install.installPath = jv["installationPath"].str;
        install.displayName = jv["displayName"].str;
        auto cat = jv["catalog"];
        install.productLineVersion = cat["productLineVersion"].str;
        install.ver = Semver(cat["productSemanticVersion"].str);
        installs ~= install;
    }
    // sorting latest first
    installs.sort!((a, b) => a.ver > b.ver);
    return VsWhereResult(true, installs);
}

private string vswhereCmd()
{
    import std.file : exists;

    const inPath = findProgram("vswhere.exe");
    if (inPath)
        return "vswhere";

    const vswhereDef = buildPath(programFiles(), "Microsoft Visual Studio",
            "Installer", "vswhere.exe");
    if (exists(vswhereDef))
    {
        return vswhereDef;
    }

    return null;
}

private string programFiles()
{
    version (Win64)
    {
        return environment.get("ProgramFiles(x86)", "C:\\Program Files(x86)");
    }
    else
    {
        return environment.get("ProgramFiles", "C:\\Program Files");
    }
}
