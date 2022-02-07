module dopamine.profile;

import dopamine.ini;
import dopamine.util;
import dopamine.msvc;

import std.algorithm;
import std.array;
import std.conv;
import std.digest.sha;
import std.exception;
import std.format;
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

enum Lang
{
    d,
    cpp,
    c,
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

    S to(A : Lang)(A val)
    {
        final switch (val)
        {
        case Lang.d:
            return "D";
        case Lang.cpp:
            return "C++";
        case Lang.c:
            return "C";
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
string toConfig(Lang val)
{
    final switch (val)
    {
    case Lang.d:
        return "d";
    case Lang.cpp:
        return "c++";
    case Lang.c:
        return "c";
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
Lang fromConfig(T : Lang)(string val)
{
    switch (val)
    {
    case "d":
        return T.d;
    case "c++":
        return T.cpp;
    case "c":
        return T.c;
    default:
        throw new Exception(format("cannot convert \"%s\" to Lang", val));
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

alias DopDigest = SHA1;

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

    private void feedDigest(ref DopDigest digest) const
    {
        feedDigestData(digest, _arch);
        feedDigestData(digest, _os);
    }

    private void describe(ref Appender!string app, int indent) const
    {
        const ind = indentStr(indent);
        app.put(format("%sArchitecture: %s\n", ind, arch.to!string));
        app.put(format("%sOS:           %s\n", ind, os.to!string));
    }

    private void writeIniSection(ref Appender!string app) const
    {
        app.put("[host]\n");
        app.put(format("arch=%s\n", _arch.toConfig()));
        app.put(format("os=%s\n", _os.toConfig()));
    }
}

/// Profile compiler information
struct Compiler
{
    private Lang _lang;
    private string _name;
    private string _ver;
    private string _path;
    version (Windows)
    {
        private VsVcInstall _vsvc;
    }

    this(Lang lang, string name, string ver, string path)
    {
        _lang = lang;
        _name = name;
        _ver = ver;
        _path = path;
    }

    version (Windows) this(Lang lang, VsVcInstall vsvc)
    {
        _lang = lang;
        _name = "MSVC";
        _ver = vsvc.ver.toString();
        _path = vsvc.installPath;
        _vsvc = vsvc;
    }

    @property Lang lang() const
    {
        return _lang;
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
        final switch (_lang)
        {
        case Lang.d:
            env["DC"] = _path;
            break;
        case Lang.cpp:
            env["CXX"] = _path;
            break;
        case Lang.c:
            env["CC"] = _path;
            break;
        }
    }

    private void describe(ref Appender!string app, int indent) const
    {
        auto ind = indentStr(indent);
        app.put(format("%s%s Compiler:\n", ind, lang.to!string));
        ind = indentStr(indent + 1);
        app.put(format("%sname:    %s\n", ind, name));
        app.put(format("%sversion: %s\n", ind, ver));
        app.put(format("%spath:    %s\n", ind, path));
        app.put(format("%sdisplay: %s\n", ind, displayName));
    }

    private void feedDigest(ref DopDigest digest) const
    {
        feedDigestData(digest, lang);
        feedDigestData(digest, name);
        feedDigestData(digest, ver);
    }

    private void writeIniSection(ref Appender!string app) const
    {
        app.put(format("[compiler.%s]\n", _lang.toConfig()));
        app.put(format("name=%s\n", _name));
        app.put(format("ver=%s\n", _ver));
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
    private Compiler[] _compilers;
    private Lang[] _langs;
    private string _digestHash;

    this(string basename, HostInfo hostInfo, BuildType buildType, Compiler[] compilers)
    {
        _basename = enforce(basename, "A profile must have a name");
        _hostInfo = hostInfo;
        _buildType = buildType;
        _compilers = compilers.sort!((a, b) => a.lang < b.lang).array;
        enforce(_compilers.length, "a Profile must have at least one compiler");

        _langs = _compilers.map!(c => c.lang).array;
        enforce(langs.equal(langs.uniq()), "cannot pass twice the same language to a profile");

        _name = _basename ~ "-" ~ _langs.map!(l => l.toConfig()).join('.');

        DopDigest digest;
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

    @property const(Lang)[] langs() const
    {
        return _langs;
    }

    @property const(Compiler)[] compilers() const
    {
        return _compilers;
    }

    const(Compiler) compilerFor(Lang lang) const
    {
        foreach (c; _compilers)
        {
            if (c.lang == lang)
                return c;
        }

        throw new Exception("No such compiler in profile: " ~ lang.to!string);
    }

    @property string digestHash() const
    {
        return _digestHash;
    }

    Profile withBasename(string basename) const
    {
        return new Profile(basename, this.hostInfo, this.buildType, this.compilers.dup);
    }

    Profile withHostInfo(HostInfo hostInfo) const
    {
        return new Profile(this.basename, hostInfo, this.buildType, this.compilers.dup);
    }

    Profile withBuildType(BuildType buildType) const
    {
        return new Profile(this.basename, this.hostInfo, buildType, this.compilers.dup);
    }

    Profile withCompilers(Compiler[] compilers) const
    {
        return new Profile(this.basename, this.hostInfo, this.buildType, compilers);
    }

    bool hasAllLangs(const(Lang)[] langs) const @trusted
    {
        import std.algorithm : canFind;

        return langs.all!(l => this.langs.canFind(l));
    }

    Profile subset(const(Lang)[] langs) const
    in (langs.length, "Cannot create a Profile subset without language")
    {
        Compiler[] comps;
        foreach (l; langs)
        {
            auto cf = _compilers.find!(c => c.lang == l);
            enforce(cf.length, format(`Language %s not in Profile %s`, l.to!string, name));
            comps ~= cf[0];
        }
        return new Profile(_basename, _hostInfo, _buildType, comps);
    }

    void collectEnvironment(ref string[string] env) const
    {
        foreach (c; _compilers)
        {
            c.collectEnvironment(env, _hostInfo.arch);
        }
    }

    void feedDigest(ref DopDigest digest) const
    {
        _hostInfo.feedDigest(digest);
        feedDigestData(digest, _buildType);
        foreach (ref c; _compilers)
        {
            c.feedDigest(digest);
        }
    }

    string describe() const
    {
        Appender!string app;

        app.put(format("Profile %s\n", name));
        _hostInfo.describe(app, 1);
        app.put(format("%sBuild type:   %s\n", indentStr(1), _buildType.toConfig));

        foreach (c; _compilers)
        {
            c.describe(app, 1);
        }

        app.put(format("%sDigest hash:  %s\n", indentStr(1), digestHash()));

        return app.data();
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

        foreach (c; _compilers)
        {
            app.put("\n");
            c.writeIniSection(app);
        }

        app.put("\n");
        app.put("[digest]\n");
        app.put(format("hash=%s\n", digestHash()));

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

        Compiler[] compilers;
        Lang[] langs;
        foreach (s; ini.sections)
        {
            enum prefix = "compiler.";
            if (!s.name.startsWith(prefix))
                continue;

            const langS = s.name[prefix.length .. $];
            const lang = fromConfig!Lang(langS);

            const cname = enforceKey(s, "name");
            const ver = enforceKey(s, "ver");
            const path = enforceKey(s, "path");

            version (Windows)
            {
                if (cname == "MSVC")
                {
                    import dopamine.semver : Semver;

                    VsVcInstall install;
                    install.ver = Semver(ver);
                    install.installPath = path;
                    install.productLineVersion = enforceKey(s, "msvc_ver");
                    install.displayName = enforceKey(s, "msvc_disp");
                    compilers ~= Compiler(lang, install);
                    langs ~= lang;
                    continue;
                }
            }

            compilers ~= Compiler(lang, cname, ver, path);
            langs ~= lang;
        }

        const suffix = nameSuffix(langs);
        if (defaultName.endsWith(suffix))
        {
            defaultName = defaultName[0 .. $ - suffix.length];
        }
        const basename = mainSec.get("basename", defaultName);

        auto p = new Profile(basename, hostInfo, buildType, compilers);

        const digestSect = ini.get("digest");
        if (digestSect)
        {
            const hash = enforceKey(digestSect, "hash");
            enforce(p.digestHash() == hash,
                "Digest hash do not match with the one of the profile file");
        }

        return p;
    }
}

version (unittest) Profile mockProfileLinux()
{
    return new Profile(
        "mock",
        HostInfo(Arch.x86_64, OS.linux),
        BuildType.debug_,
        [
            Compiler(Lang.d, "DMD", "2.098.1", "/usr/bin/dmd"),
            Compiler(Lang.cpp, "G++", "11.1.0", "/usr/bin/g++"),
            Compiler(Lang.c, "GCC", "11.1.0", "/usr/bin/gcc"),
        ]
    );
}

private static string nameSuffix(const(Lang)[] langs)
in (langs.length)
in (isStrictlyMonotonic(langs))
in (langs.uniq().equal(langs))
{
    return "-" ~ langs.map!(l => l.toConfig()).join("-");
}

string profileName(string basename, const(Lang)[] langs)
{
    enforce(!hasDuplicates(langs));

    string suffix;
    if (!isStrictlyMonotonic(langs))
    {
        Lang[] ll = langs.dup;
        sort(ll);
        suffix = nameSuffix(ll);
    }
    else
    {
        suffix = nameSuffix(langs);
    }
    return basename ~ suffix;
}

string profileDefaultName(const(Lang)[] langs)
{
    return profileName("default", langs);
}

string profileIniName(string basename, const(Lang)[] langs)
{
    return profileName(basename, langs) ~ ".ini";
}

Lang[] strToLangs(const(string)[] langs)
{
    return langs.map!(l => l.fromConfig!Lang).array;
}

Lang strToLang(string lang)
{
    return lang.fromConfig!Lang;
}

string[] strFromLangs(const(Lang)[] langs)
{
    return langs.map!(l => l.toConfig()).array;
}

string strFromLang(Lang lang)
{
    return lang.toConfig();
}

Profile detectDefaultProfile(Lang[] langs)
{
    auto hostInfo = currentHostInfo();

    enforce(langs.sort().uniq().equal(langs), "cannot build a profile with twice the same language");

    Compiler[] compilers;
    foreach (lang; langs)
    {
        compilers ~= detectDefaultCompiler(lang);
    }

    return new Profile("default", hostInfo, BuildType.debug_, compilers);
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

Compiler detectDefaultCompiler(Lang lang)
{
    foreach (detectF; defaultDetectOrder[lang])
    {
        auto comp = detectF();
        if (comp)
            return comp;
    }

    throw new Exception(format("could not find a compiler for %s language", lang.to!string));
}

alias CompilerDetectF = Compiler function();

immutable CompilerDetectF[][Lang] defaultDetectOrder;

shared static this() @trusted
{
    CompilerDetectF[][Lang] order;

    order[Lang.d] = [&detectLdc, &detectDmd];

    version (OSX)
    {
        order[Lang.c] = [&detectClang, &detectGcc];
        order[Lang.cpp] = [&detectClangpp, &detectGpp];
    }
    else version (Posix)
    {
        order[Lang.c] = [&detectGcc, &detectClang];
        order[Lang.cpp] = [&detectGpp, &detectClangpp];
    }
    else version (Windows)
    {
        order[Lang.c] = [&detectMsvcC, &detectGcc, &detectClang];
        order[Lang.cpp] = [&detectMsvcCpp, &detectGpp, &detectClangpp];
    }

    import std.exception : assumeUnique;

    defaultDetectOrder = assumeUnique(order);
}

string indentStr(int indent)
{
    return replicate("  ", indent);
}

version (Windows)
{
    Compiler detectMsvcC()
    {
        return detectMsvc(Lang.c);
    }

    Compiler detectMsvcCpp()
    {
        return detectMsvc(Lang.cpp);
    }

    Compiler detectMsvc(Lang lang) @trusted
    {
        import dopamine.msvc : VsWhereResult, runVsWhere;

        const result = runVsWhere();
        if (!result || !result.installs.length)
            return Compiler.init;

        return Compiler(lang, result.installs[0]);
    }
}

string extractCompilerVersion(string versionOutput, string re)
{
    import std.exception : enforce;
    import std.regex : matchFirst, regex;

    auto verMatch = matchFirst(versionOutput, regex(re, "m"));
    enforce(verMatch.length >= 2, format("Compiler version not found. Command output:\n%s",
            versionOutput));
    return verMatch[1];
}

Compiler detectCompiler(string[] command, string re, string name, Lang lang)
in (command.length >= 1)
{
    import std.process : execute, Config;

    command[0] = findProgram(command[0]);
    if (!command[0])
        return Compiler.init;

    auto result = execute(command, null, Config.suppressConsole);
    if (result.status != 0)
        return Compiler.init;

    const ver = extractCompilerVersion(result.output, re);

    const path = command[0];

    return Compiler(lang, name, ver, path);
}

enum ldcVersionRe = `^LDC.*\((\d+\.\d+\.\d+[A-Za-z0-9.+-]*)\):$`;
enum dmdVersionRe = `^DMD.*v(\d+\.\d+\.\d+[A-Za-z0-9.+-]*)$`;
enum gccVersionRe = `^gcc.* (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)( .*)?$`;
enum gppVersionRe = `^g\+\+.* (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)( .*)?$`;
enum clangVersionRe = `clang version (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)`;

Compiler detectLdc()
{
    auto comp = detectCompiler(["ldc", "--version"], ldcVersionRe, "LDC", Lang.d);
    if (!comp)
        comp = detectCompiler(["ldc2", "--version"], ldcVersionRe, "LDC", Lang.d);

    return comp;
}

Compiler detectDmd()
{
    return detectCompiler(["dmd", "--version"], dmdVersionRe, "DMD", Lang.d);
}

Compiler detectGcc()
{
    return detectCompiler(["gcc", "--version"], gccVersionRe, "GCC", Lang.c);
}

Compiler detectGpp()
{
    return detectCompiler(["g++", "--version"], gppVersionRe, "G++", Lang.cpp);
}

Compiler detectClang()
{
    return detectCompiler(["clang", "--version"], clangVersionRe, "CLANG", Lang.c);
}

Compiler detectClangpp()
{
    return detectCompiler(["clang++", "--version"], clangVersionRe, "CLANG++", Lang.cpp);
}

@("extract Clang version")
unittest
{
    auto output = import("clang-version-13.0.0.txt");
    assert(extractCompilerVersion(output, clangVersionRe) == "13.0.0");
}

@("extract gcc/g++ version")
unittest
{
    auto output = import("gcc-version-11.1.0.txt");
    assert(extractCompilerVersion(output, gccVersionRe) == "11.1.0");
    output = import("g++-version-11.1.0.txt");
    assert(extractCompilerVersion(output, gppVersionRe) == "11.1.0");
}

@("extract DMD version")
unittest
{
    auto output = import("dmd-version-2.098.1.txt");
    assert(extractCompilerVersion(output, dmdVersionRe) == "2.098.1");
}

@("extract LDC version")
unittest
{
    auto output = import("ldc-version-1.28.1.txt");
    assert(extractCompilerVersion(output, ldcVersionRe) == "1.28.1");
}
