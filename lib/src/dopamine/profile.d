module dopamine.profile;

import dopamine.util;

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

alias DopDigest = SHA1;

/// Profile host information
class HostInfo
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
class Compiler
{
    private Lang _lang;
    private string _name;
    private string _ver;
    private string _path;

    this(Lang lang, string name, string ver, string path)
    {
        _lang = lang;
        _name = name;
        _ver = ver;
        _path = path;
    }

    @property Lang lang() const
    {
        return _lang;
    }

    @property string name() const
    {
        return _name;
    }

    @property string ver() const
    {
        return _ver;
    }

    @property string path() const
    {
        return _path;
    }

    private void collectEnvironment(ref string[string] env) const
    {
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
        app.put(format("path=%s\n", _path));
    }
}

final class Profile
{
    private string _name;
    private HostInfo _hostInfo;
    private BuildType _buildType;
    private Compiler[] _compilers;

    this(string name, HostInfo hostInfo, BuildType buildType, Compiler[] compilers)
    {
        _name = enforce(name, "A profile must have a name");
        _hostInfo = hostInfo;
        _buildType = buildType;
        _compilers = compilers.sort!((a, b) => a.lang < b.lang).array;

        auto langs = _compilers.map!(c => c.lang).array;
        enforce(langs.equal(langs.uniq()), "cannot pass twice the same language to a profile");
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

    void collectEnvironment(ref string[string] env) const
    {
        foreach (c; _compilers)
        {
            c.collectEnvironment(env);
        }
    }

    void feedDigest(ref DopDigest digest) const
    {
        _hostInfo.feedDigest(digest);
        feedDigestData(digest, _buildType);
        foreach (c; _compilers)
        {
            c.feedDigest(digest);
        }
    }

    string digestHash() const
    {
        DopDigest digest;
        feedDigest(digest);
        return toHexString!(LetterCase.lower)(digest.finish()).idup;
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
        import std.file : read;
        import std.path : baseName, stripExtension;

        const ini = cast(string) assumeUnique(read(filename));
        const nameFromFile = baseName(stripExtension(filename));

        return Profile.fromIni(ini, nameFromFile);
    }

    private string toIni(bool withName) const
    {
        Appender!string app;

        app.put("[main]\n");
        if (withName)
        {
            app.put(format("name=%s\n", _name));
        }
        app.put(format("buildtype=%s\n", _buildType));

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
        import dini : Ini, IniSection;

        auto ini = Ini.ParseString(iniString);

        auto enforceSection(string name)
        {
            enforce(ini.hasSection(name),
                    format("Ill-formed profile file: [%s] section is required", name));
            return ini.getSection(name);
        }

        string enforceKey(ref IniSection section, string key)
        {
            enforce(section.hasKey(key),
                    format("Ill-formed profile file: \"%s\" field is required in the [%s] section",
                        key, section.name));
            return section.getKey(key);
        }

        auto mainSec = enforceSection("main");
        auto hostSec = enforceSection("host");

        const name = mainSec.hasKey("name") ? mainSec.getKey("name") : defaultName;
        const buildType = enforceKey(mainSec, "buildtype").fromConfig!BuildType();

        const arch = enforceKey(hostSec, "arch").fromConfig!Arch();
        const os = enforceKey(hostSec, "os").fromConfig!OS();
        auto hostInfo = new HostInfo(arch, os);

        Compiler[] compilers;
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

            compilers ~= new Compiler(lang, cname, ver, path);
        }

        auto p = new Profile(name, hostInfo, buildType, compilers);

        if (ini.hasSection("digest"))
        {
            const hash = enforceKey(ini["digest"], "hash");
            enforce(p.digestHash() == hash,
                    "Digest hash do not match with the one of the profile file");
        }

        return p;
    }
}

Lang[] toLangs(const(string)[] langs)
{
    return langs.map!(l => l.fromConfig!Lang).array;
}

string defaultProfileName(Lang[] langs)
{
    enforce(langs.length, "at least one language is needed");
    return "default-" ~ langs.sort().map!(l => l.toConfig()).join("-");
}

Profile detectDefaultProfile(Lang[] langs)
{
    const name = defaultProfileName(langs);
    auto hostInfo = currentHostInfo();

    enforce(langs.sort().uniq().equal(langs), "cannot build a profile with twice the same language");

    Compiler[] compilers;
    foreach (lang; langs)
    {
        compilers ~= enforce(detectDefaultCompiler(lang),
                "could not find a compiler for %s language", lang.to!string);
    }

    return new Profile(name, hostInfo, BuildType.release, compilers);
}

private:

import dopamine.util;

import std.process;
import std.regex;

// import std.stdio;

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

    return new HostInfo(arch, os);
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
        throw new Exception(format("cannot convert %s to Arch", val));
    }
}

OS fromConfig(T : OS)(string val)
{
    switch (val)
    {
    case "linux":
        return T.linux;
    case "windows":
        return T.windows;
    default:
        throw new Exception(format("cannot convert %s to OS", val));
    }
}

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
        throw new Exception(format("cannot convert %s to Lang", val));
    }
}

BuildType fromConfig(T : BuildType)(string val)
{
    switch (val)
    {
    case "release":
        return T.release;
    case "debut":
        return T.debug_;
    default:
        throw new Exception(format("cannot convert %s to Build Type", val));
    }
}

Compiler detectDefaultCompiler(Lang lang)
{
    foreach (detectF; defaultDetectOrder[lang])
    {
        auto comp = detectF();
        if (comp)
            return comp;
    }

    return null;
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
        static assert(false, "not implemented");
    }

    import std.exception : assumeUnique;

    defaultDetectOrder = assumeUnique(order);
}

string indentStr(int indent)
{
    return replicate("  ", indent);
}

Compiler detectCompiler(string[] command, string re, string name, Lang lang)
in(command.length >= 1)
{
    command[0] = findProgram(command[0]);
    if (!command[0])
        return null;

    auto result = execute(command, null, Config.suppressConsole);
    if (result.status != 0)
        return null;

    auto verMatch = matchFirst(result.output, regex(re, "m"));
    if (verMatch.length < 2)
    {
        throw new Exception(format("Could not determine %s version. Command output:\n%s",
                name, result.output));
    }
    const ver = verMatch[1];
    const path = command[0];

    return new Compiler(lang, name, ver, path);
}

Compiler detectLdc()
{
    enum versionRe = `^LDC.*\((\d+\.\d+\.\d+[A-Za-z0-9.+-]*)\):$`;

    auto comp = detectCompiler(["ldc", "--version"], versionRe, "LDC", Lang.d);
    if (!comp)
        comp = detectCompiler(["ldc2", "--version"], versionRe, "LDC", Lang.d);

    return comp;
}

Compiler detectDmd()
{
    enum versionRe = `^DMD.*v(\d+\.\d+\.\d+[A-Za-z0-9.+-]*)$`;

    return detectCompiler(["dmd", "--version"], versionRe, "DMD", Lang.d);
}

Compiler detectGcc()
{
    enum versionRe = `^gcc.* (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)$`;

    return detectCompiler(["gcc", "--version"], versionRe, "GCC", Lang.c);
}

Compiler detectGpp()
{
    enum versionRe = `^g\+\+.* (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)$`;

    return detectCompiler(["g++", "--version"], versionRe, "G++", Lang.cpp);
}

Compiler detectClang()
{
    enum versionRe = `^clang.* (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)$`;

    return detectCompiler(["clang", "--version"], versionRe, "CLANG", Lang.c);
}

Compiler detectClangpp()
{
    enum versionRe = `^clang.* (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)$`;

    return detectCompiler(["clang++", "--version"], versionRe, "CLANG++", Lang.cpp);
}
