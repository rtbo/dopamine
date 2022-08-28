module dopamine.profile;

import dopamine.ini;
import dopamine.util;
import dopamine.msvc;

import std.algorithm;
import std.array;
import std.conv;
import std.digest;
import std.exception;
import std.format;
import std.range;
import std.string;

@safe:

enum Arch
{
    x86_64,
    x86,
}

enum OS
{
    linux,
    windows,
}

enum BuildType
{
    release,
    debug_,
}

/// print human readable string of the profile enums
template to(S : string)
{
    S to(A : Arch)(A val)
    {
        final switch (val)
        {
        case Arch.x86:
            return "X86";
        case Arch.x86_64:
            return "X86-64";
        }
    }

    S to(A : BuildType)(A val)
    {
        final switch (val)
        {
        case BuildType.release:
            return "Release";
        case BuildType.debug_:
            return "Debug";
        }
    }

    S to(A : OS)(A val)
    {
        final switch (val)
        {
        case OS.linux:
            return "Linux";
        case OS.windows:
            return "Windows";
        }
    }
}

/// Translate enums to config file string
string toConfig(Arch val)
{
    final switch (val)
    {
    case Arch.x86:
        return "x86";
    case Arch.x86_64:
        return "x86_64";
    }
}

/// ditto
string toConfig(OS val)
{
    final switch (val)
    {
    case OS.linux:
        return "linux";
    case OS.windows:
        return "windows";
    }
}

/// ditto
string toConfig(BuildType val)
{
    final switch (val)
    {
    case BuildType.release:
        return "release";
    case BuildType.debug_:
        return "debug";
    }
}

/// Translate config file string to enum
T fromConfig(T)(string val) if (is(T == enum));

Arch fromConfig(T : Arch)(string val)
{
    switch (val)
    {
    case "x86":
        return T.x86;
    case "x86_64":
        return T.x86_64;
    default:
        throw new Exception(format("cannot convert \"%s\" to Arch", val));
    }
}

/// ditto
OS fromConfig(T : OS)(string val)
{
    switch (val)
    {
    case "linux":
        return T.linux;
    case "windows":
        return T.windows;
    default:
        throw new Exception(format("cannot convert \"%s\" to OS", val));
    }
}

/// ditto
BuildType fromConfig(T : BuildType)(string val)
{
    switch (val)
    {
    case "release":
        return T.release;
    case "debug":
        return T.debug_;
    default:
        throw new Exception(format("cannot convert \"%s\" to Build Type", val));
    }
}

/// Profile host information
struct HostInfo
{
    private Arch _arch;
    private OS _os;

    this(Arch arch, OS os)
    {
        _arch = arch;
        _os = os;
    }

    @property Arch arch() const
    {
        return _arch;
    }

    @property OS os() const
    {
        return _os;
    }

    private void feedDigest(D)(ref D digest) const
    if (isDigest!D)
    {
        feedDigestData(digest, _arch);
        feedDigestData(digest, _os);
    }

    private void describe(O)(O output, int indent) const
    if (isOutputRange!(O, char))
    {
        const ind = indentStr(indent);
        output.put(format("%sArchitecture: %s\n", ind, arch.to!string));
        output.put(format("%sOS:           %s\n", ind, os.to!string));
    }

    private void writeIniSection(ref Appender!string app) const
    {
        app.put("[host]\n");
        app.put(format("arch=%s\n", _arch.toConfig()));
        app.put(format("os=%s\n", _os.toConfig()));
    }
}

/// A tool necessary to build the recipe and for which
/// the version affects the Build-Id
struct Tool
{
    private string _id; // e.g. "cc", "c++", "dc"
    private string _name; // e.g. "dmd", "gcc", ...
    private string _ver; // version
    private string _path; // executable path
    version (Windows)
    {
        // only for MSVC compiler
        private VsVcInstall _vsvc;
    }

    this(string id, string name, string ver, string path)
    {
        _id = id;
        _name = name;
        _ver = ver;
        _path = path;
    }

    version (Windows) this(string id, VsVcInstall vsvc)
    {
        // either cc or c++
        _id = id;
        _name = "MSVC";
        _ver = vsvc.ver.toString();
        _path = vsvc.installPath;
        _vsvc = vsvc;
    }

    static Tool detect(string id)
    {
        return detectTool(id);
    }

    @property string id() const
    {
        return _id;
    }

    @property string name() const
    {
        return _name;
    }

    @property string displayName() const
    {
        version (Windows)
        {
            if (_vsvc)
                return _vsvc.displayName;
        }
        return _name ~ "-" ~ _ver;
    }

    @property string ver() const
    {
        return _ver;
    }

    @property string path() const
    {
        return _path;
    }

    version (Windows)
    {
        @property VsVcInstall vsvc() const
        {
            return _vsvc;
        }
    }

    bool opCast(T : bool)() const
    {
        return _name.length && _ver.length && _path.length;
    }

    private void collectEnvironment(ref string[string] env, Arch arch) const @trusted
    {
        version (Windows)
        {
            if (_vsvc)
            {
                _vsvc.collectEnvironment(env, arch, arch);
                return;
            }
        }
        switch (_name)
        {
        case "dc":
            env["DC"] = _path;
            break;
        case "c++":
            env["CXX"] = _path;
            break;
        case "cc":
            env["CC"] = _path;
            break;
        default:
            break;
        }
    }

    private void describe(O)(O output, int indent) const
    if (isOutputRange!(O, char))
    {
        auto ind = indentStr(indent);
        output.put(format("%sTool %s:\n", ind, id));
        ind = indentStr(indent + 1);
        output.put(format("%sname:    %s\n", ind, name));
        output.put(format("%sversion: %s\n", ind, ver));
        output.put(format("%spath:    %s\n", ind, path));
        output.put(format("%sdisplay: %s\n", ind, displayName));
    }

    private void feedDigest(D)(ref D digest) const
    if (isDigest!D)
    {
        feedDigestData(digest, id);
        feedDigestData(digest, name);
        feedDigestData(digest, ver);
    }

    private void writeIniSection(ref Appender!string app) const
    {
        app.put(format("[tool.%s]\n", _id));
        app.put(format("name=%s\n", _name));
        app.put(format("version=%s\n", _ver));
        version (Windows)
        {
            app.put(format("path=%s\n", _path.replace("\\", "\\\\")));
            if (_vsvc)
            {
                app.put(format("msvc_ver=%s\n", _vsvc.productLineVersion));
                app.put(format("msvc_disp=%s\n", _vsvc.displayName));
            }
        }
        else
        {
            app.put(format("path=%s\n", _path));
        }
    }
}

final class Profile
{
    private string _basename;
    private string _name;
    private HostInfo _hostInfo;
    private BuildType _buildType;
    private Tool[] _tools;
    private string _digestHash;

    this(string basename, HostInfo hostInfo, BuildType buildType, Tool[] tools)
    {
        import std.digest.sha : SHA1;

        _basename = enforce(basename, "A profile must have a name");
        _hostInfo = hostInfo;
        _buildType = buildType;
        _tools = tools.sort!((a, b) => a.id < b.id).array;
        enforce(_tools.length, "a Profile must have at least one tool");

        string[] toolIds = tools.map!(t => t.id).array;
        enforce(toolIds.equal(toolIds.uniq()), "cannot pass twice the same language to a profile");

        _name = _basename ~ "-" ~ toolIds.join('.');

        SHA1 digest;
        feedDigest(digest);
        _digestHash = toHexString!(LetterCase.lower)(digest.finish()).idup;
    }

    @property string basename() const
    {
        return _basename;
    }

    @property string name() const
    {
        return _name;
    }

    @property const(HostInfo) hostInfo() const
    {
        return _hostInfo;
    }

    @property BuildType buildType() const
    {
        return _buildType;
    }

    @property const(Tool)[] tools() const
    {
        return _tools;
    }

    const(Tool) toolFor(string id) const
    {
        foreach (t; _tools)
        {
            if (t.id == id)
                return t;
        }

        throw new Exception("No such tool in profile: " ~ id);
    }

    @property string digestHash() const
    {
        return _digestHash;
    }

    Profile withBasename(string basename) const
    {
        return new Profile(basename, this.hostInfo, this.buildType, this.tools.dup);
    }

    Profile withHostInfo(HostInfo hostInfo) const
    {
        return new Profile(this.basename, hostInfo, this.buildType, this.tools.dup);
    }

    Profile withBuildType(BuildType buildType) const
    {
        return new Profile(this.basename, this.hostInfo, buildType, this.tools.dup);
    }

    Profile withTools(Tool[] tools) const
    {
        return new Profile(this.basename, this.hostInfo, this.buildType, tools);
    }

    bool hasTool(string id) const @trusted
    {
        import std.algorithm : canFind;

        return tools.map!(t => t.id).canFind(id);
    }

    bool hasAllTools(const(string)[] ids) const @trusted
    {
        import std.algorithm : all;

        return ids.all!(id => this.hasTool(id));
    }

    Profile subset(const(string)[] toolIds) const
    in (toolIds.length, "Cannot create a Profile subset without tool")
    {
        Tool[] tools;
        foreach (id; toolIds)
        {
            auto tf = _tools.find!(t => t.id == id);
            enforce(tf.length, format(`Tool %s not in Profile %s`, id, name));
            tools ~= tf[0];
        }
        return new Profile(_basename, _hostInfo, _buildType, tools);
    }

    void collectEnvironment(ref string[string] env) const
    {
        foreach (t; _tools)
        {
            t.collectEnvironment(env, _hostInfo.arch);
        }
    }

    void feedDigest(D)(ref D digest) const
    if (isDigest!D)
    {
        _hostInfo.feedDigest(digest);
        feedDigestData(digest, _buildType);
        foreach (ref t; _tools)
        {
            t.feedDigest(digest);
        }
    }

    void describe(O)(O output) const
    if (isOutputRange!(O, char))
    {
        output.put(format("Profile %s\n", name));
        _hostInfo.describe(output, 1);
        output.put(format("%sBuild type:   %s\n", indentStr(1), _buildType.toConfig));

        foreach (t; _tools)
        {
            t.describe(output, 1);
        }

        output.put(format("%sDigest hash:  %s\n", indentStr(1), digestHash()));
    }

    void saveToFile(string path, bool withName = true, bool mkdir = false) const
    {
        import std.file : mkdirRecurse, write;
        import std.path : dirName;

        if (mkdir)
        {
            mkdirRecurse(dirName(path));
        }

        write(path, toIni(withName));
    }

    /// Load a [Profile] from ini file.
    /// if ini do not have a name field, name will be assessed from the filename
    static Profile loadFromFile(string filename) @trusted
    {
        import std.exception : assumeUnique;
        import std.path : baseName, stripExtension;
        import std.stdio : File;
        import std.file : read;

        const nameFromFile = baseName(stripExtension(filename));

        auto f = File(filename, "r");
        return parseIniProfile(parseIni(f.byLine()), nameFromFile);
    }

    private string toIni(bool withName) const
    {
        Appender!string app;

        app.put("[main]\n");
        if (withName)
        {
            app.put(format("basename=%s\n", _basename));
        }
        app.put(format("buildtype=%s\n", _buildType.toConfig));

        app.put("\n");
        _hostInfo.writeIniSection(app);

        foreach (t; _tools)
        {
            app.put("\n");
            t.writeIniSection(app);
        }

        return app.data();
    }

    static Profile fromIni(string iniString, string defaultName) @trusted
    {
        import std.string : lineSplitter;

        return parseIniProfile(parseIni(lineSplitter(iniString)), defaultName);
    }

    private static Profile parseIniProfile(Ini ini, string defaultName)
    {
        auto enforceSection(string name)
        {
            const sect = ini.get(name);
            enforce(sect, format("Ill-formed profile file: [%s] section is required", name));
            return sect;
        }

        string enforceKey(in Section section, in string key)
        {
            const val = section.get(key);
            enforce(val, format("Ill-formed profile file: \"%s\" field is required in the [%s] section",
                    key, section.name));
            return val;
        }

        auto mainSec = enforceSection("main");
        auto hostSec = enforceSection("host");

        const buildType = enforceKey(mainSec, "buildtype").fromConfig!BuildType();

        const arch = enforceKey(hostSec, "arch").fromConfig!Arch();
        const os = enforceKey(hostSec, "os").fromConfig!OS();
        auto hostInfo = HostInfo(arch, os);

        Tool[] tools;
        foreach (s; ini.sections)
        {
            enum prefix = "tool.";
            if (!s.name.startsWith(prefix))
                continue;

            const id = s.name[prefix.length .. $];
            const tname = enforceKey(s, "name");
            const ver = enforceKey(s, "version");
            const path = enforceKey(s, "path");

            version (Windows)
            {
                if (tname == "MSVC")
                {
                    import dopamine.semver : Semver;

                    VsVcInstall install;
                    install.ver = Semver(ver);
                    install.installPath = path;
                    install.productLineVersion = enforceKey(s, "msvc_ver");
                    install.displayName = enforceKey(s, "msvc_disp");
                    tools ~= Tool(id, install);
                    continue;
                }
            }

            tools ~= Tool(id, tname, ver, path);
        }

        const suffix = nameSuffix(tools.map!(t => t.id).array);
        if (defaultName.endsWith(suffix))
        {
            defaultName = defaultName[0 .. $ - suffix.length];
        }
        const basename = mainSec.get("basename", defaultName);

        return new Profile(basename, hostInfo, buildType, tools);
    }
}

/// Return a mock profile typical of a linux system
version (unittest) Profile mockProfileLinux()
{
    return new Profile(
        "mock",
        HostInfo(Arch.x86_64, OS.linux),
        BuildType.debug_,
        [
            Tool("dc", "DMD", "2.098.1", "/usr/bin/dmd"),
            Tool("c++", "G++", "11.1.0", "/usr/bin/g++"),
            Tool("cc", "GCC", "11.1.0", "/usr/bin/gcc"),
        ]
    );
}

private string nameSuffix(string[] ids)
in (ids.length)
in (isStrictlyMonotonic(ids))
in (ids.uniq().equal(ids))
{
    return "-" ~ ids.join("-");
}

string profileName(string basename, const(string)[] toolIds)
{
    string[] ids = toolIds.dup;
    enforce(!hasDuplicates(ids));

    if (!isStrictlyMonotonic(ids))
        sort(ids);

    return basename ~ nameSuffix(ids);
}

string profileDefaultName(const(string)[] toolIds)
{
    return profileName("default", toolIds);
}

string profileIniName(string basename, const(string)[] toolIds)
{
    return profileName(basename, toolIds) ~ ".ini";
}

Profile detectDefaultProfile(string[] toolIds, Flag!"allowMissing" allowMissing)
{
    auto hostInfo = currentHostInfo();

    enforce(toolIds.sort().uniq().equal(toolIds), "cannot build a profile with twice the same tool");

    Tool[] tools;
    foreach (id; toolIds)
    {
        try
        {
            tools ~= detectTool(id);
        }
        catch (ToolVersionParseException ex)
        {
            throw ex;
        }
        catch (Exception ex)
        {
            if (!allowMissing)
            {
                throw ex;
            }
        }
    }

    if (!tools.length)
        throw new Exception("No tool found, cannot initialize profile");

    return new Profile("default", hostInfo, BuildType.debug_, tools);
}

class ToolVersionParseException : Exception
{
    this(string name, string[] cmd, string output, string file = __FILE__, size_t line = __LINE__)
    {
        import std.process : escapeShellCommand;

        super(format(
                "Could not parse version of %s from \"%s\" output:\n",
                name, escapeShellCommand(cmd), output,
        ), file, line);
    }
}

private:

import dopamine.util;

HostInfo currentHostInfo()
{
    version (X86_64)
    {
        const arch = Arch.x86_64;
    }
    else version (X86)
    {
        const arch = Arch.x86;
    }
    else
    {
        static assert(false, "unsupported architecture");
    }

    version (Windows)
    {
        const os = OS.windows;
    }
    else version (linux)
    {
        const os = OS.linux;
    }
    else
    {
        static assert(false, "unsupported OS");
    }

    return HostInfo(arch, os);
}

Tool detectTool(string id)
{
    switch (id)
    {
        case "cc":
            return detectCc();
        case "c++":
            return detectCpp();
        case "dc":
            return detectDc();
        default:
            return detectToolGeneric([id, "--version"], genericRe, id, id);
    }
}

Tool detectCc()
{
    version (OSX)
    {
        auto order = [&detectClang, &detectGcc];
    }
    else version (Posix)
    {
        auto order = [&detectGcc, &detectClang];
    }
    else version (Windows)
    {
        auto order = [&detectMsvcC, &detectGcc, &detectClang];
    }

    return detectInOrder("cc", order);
}

Tool detectCpp()
{
    version (OSX)
    {
        auto order = [&detectClangpp, &detectGpp];
    }
    else version (Posix)
    {
        auto order = [&detectGpp, &detectClangpp];
    }
    else version (Windows)
    {
        auto order = [&detectMsvcCpp, &detectGpp, &detectClangpp];
    }

    return detectInOrder("c++", order);
}

Tool detectDc()
{
    return detectInOrder("dc", [&detectLdc, &detectDmd]);
}

alias ToolDetectF = Tool function();

Tool detectInOrder(string id, ToolDetectF[] order)
{
    foreach (f; order)
    {
        Tool t = f();
        if (t)
            return t;
    }

    throw new Exception("Could not find any tool \"" ~ id ~ "\"");
}

string indentStr(int indent)
{
    return replicate("  ", indent);
}

version (Windows)
{
    Tool detectMsvcC()
    {
        return detectMsvc("cc");
    }

    Tool detectMsvcCpp()
    {
        return detectMsvc("c++");
    }

    Tool detectMsvc(string id) @trusted
    {
        import dopamine.msvc : VsWhereResult, runVsWhere;

        const result = runVsWhere();
        if (!result || !result.installs.length)
            return Tool.init;

        return Tool(id, result.installs[0]);
    }
}

string extractToolVersion(string versionOutput, string re)
{
    import std.exception : enforce;
    import std.regex : matchFirst, regex;

    auto verMatch = matchFirst(versionOutput, regex(re, "m"));
    enforce(verMatch.length >= 2);
    return verMatch[1];
}

Tool detectToolGeneric(string[] command, string re, string id, string name)
in (command.length >= 1)
{
    import std.process : execute, Config;

    command[0] = findProgram(command[0]);
    if (!command[0])
        return Tool.init;

    auto result = execute(command, null, Config.suppressConsole);
    if (result.status != 0)
        return Tool.init;

    const path = command[0];

    try
    {
        const ver = extractToolVersion(result.output, re);
        return Tool(id, name, ver, path);
    }
    catch (Exception ex)
    {
        throw new ToolVersionParseException(
            name, command, result.output
        );
    }
}

enum genericRe = `(\d+\.\d+\.\d+[A-Za-z0-9.+-]*)`;
enum ldcVersionRe = `^LDC.*\((\d+\.\d+\.\d+[A-Za-z0-9.+-]*)\):$`;
enum dmdVersionRe = `^DMD.*v(\d+\.\d+\.\d+[A-Za-z0-9.+-]*)$`;
enum gccVersionRe = `^gcc.* (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)( .*)?$`;
enum gppVersionRe = `^g\+\+.* (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)( .*)?$`;
enum clangVersionRe = `clang version (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)`;

Tool detectLdc()
{
    auto comp = detectToolGeneric(["ldc", "--version"], ldcVersionRe, "dc", "LDC");
    if (!comp)
        comp = detectToolGeneric(["ldc2", "--version"], ldcVersionRe, "dc", "LDC");

    return comp;
}

Tool detectDmd()
{
    return detectToolGeneric(["dmd", "--version"], dmdVersionRe, "dc", "DMD");
}

Tool detectGcc()
{
    return detectToolGeneric(["gcc", "--version"], gccVersionRe, "cc", "GCC");
}

Tool detectGpp()
{
    return detectToolGeneric(["g++", "--version"], gppVersionRe, "c++", "G++");
}

Tool detectClang()
{
    return detectToolGeneric(["clang", "--version"], clangVersionRe, "cc", "CLANG");
}

Tool detectClangpp()
{
    return detectToolGeneric(["clang++", "--version"], clangVersionRe, "c++", "CLANG++");
}

version(unittest)
{
    import unit_threaded.assertions;
}

@("extract Clang version")
unittest
{
    auto output = import("version-clang-13.0.0.txt");
    extractToolVersion(output, clangVersionRe).should == "13.0.0";
}

@("extract gcc/g++ version")
unittest
{
    auto output = import("version-gcc-11.1.0.txt");
    extractToolVersion(output, gccVersionRe).should == "11.1.0";

    output = import("version-g++-11.1.0.txt");
    extractToolVersion(output, gppVersionRe).should == "11.1.0";

    output = import("version-gcc-8.1.0-x86_64-posix-seh-rev0-mingw.txt");
    extractToolVersion(output, gccVersionRe).should == "8.1.0";

    output = import("version-g++-8.1.0-x86_64-posix-seh-rev0-mingw.txt");
    extractToolVersion(output, gppVersionRe).should == "8.1.0";
}

@("extract DMD version")
unittest
{
    auto output = import("version-dmd-2.098.1.txt");
    extractToolVersion(output, dmdVersionRe).should == "2.098.1";
}

@("extract LDC version")
unittest
{
    auto output = import("version-ldc-1.28.1.txt");
    extractToolVersion(output, ldcVersionRe).should == "1.28.1";
}

@("extract Python version")
unittest
{
    auto output = "Python 3.10.6";
    extractToolVersion(output, genericRe).should == "3.10.6";
}
