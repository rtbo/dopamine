module dopamine.profile;

import dopamine.util;

import std.algorithm;
import std.array;
import std.conv;
import std.digest.sha;
import std.exception;
import std.format;
import std.string;

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

class Compiler
{
    Lang lang;

    string name;
    string ver;
    string path;

    void collectEnvironment(ref string[string] env) const
    {
        final switch (lang)
        {
        case Lang.d:
            env["DC"] = path;
            break;
        case Lang.cpp:
            env["CXX"] = path;
            break;
        case Lang.c:
            env["CC"] = path;
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
    }

    private void feedDigest(ref DopDigest digest) const
    {
        feedDigestData(digest, lang);
        feedDigestData(digest, name);
        feedDigestData(digest, ver);
    }

    private void writeIniSection(ref Appender!string app) const
    {
        app.put("\n");
        app.put(format("[compiler.%s]\n", lang.toConfig));
        app.put(format("name=%s\n", name));
        app.put(format("version=%s\n", ver));
        app.put(format("path=%s\n", path));
    }
}

class Profile
{
    string name;
    Arch arch;
    OS os;
    BuildType buildType;
    Compiler[Lang] compilers;

    void collectEnvironment(ref string[string] env) const
    {
        foreach (c; compilers)
        {
            c.collectEnvironment(env);
        }
    }

    final string digestHash() const
    {
        DopDigest digest;
        feedDigest(digest);
        return toHexString!(LetterCase.lower)(digest.finish()).idup;
    }

    void feedDigest(ref DopDigest digest) const
    {
        feedDigestData(digest, arch);
        feedDigestData(digest, os);
        feedDigestData(digest, buildType);
        foreach (c; compilers)
        {
            c.feedDigest(digest);
        }
    }

    string describe() const
    {
        auto app = appender!string;

        app.put(format("Profile: %s\n", name));

        auto ind = indentStr(1);
        app.put(format("%sArch:       %s\n", ind, arch.to!string));
        app.put(format("%sOS:         %s\n", ind, os.to!string));
        app.put(format("%sBuild type: %s\n", ind, buildType.to!string));

        foreach (c; compilers)
        {
            c.describe(app, 1);
        }

        return app.data[0 .. $ - 1]; // remove last \n
    }

    string toIni(bool withName = true) const
    {
        auto app = appender!string;

        app.put("[main]\n");
        if (withName)
            app.put(format("name=%s\n", name));
        app.put(format("arch=%s\n", arch.toConfig));
        app.put(format("os=%s\n", os.toConfig));
        app.put(format("buildtype=%s\n", buildType.toConfig));

        foreach (c; compilers)
        {
            c.writeIniSection(app);
        }

        app.put("\n");
        app.put("[digest]\n");
        app.put(format("hash=%s\n", digestHash()));

        return app.data;
    }

    void saveToFile(string path, bool withName = true, bool mkdir = false) const
    {
        import std.file : mkdirRecurse, write;
        import std.path : dirName;

        if (mkdir)
        {
            mkdirRecurse(dirName(path));
        }

        write(path, toIni());
    }

    static Profile fromIni(string iniString)
    {
        import dini : Ini;

        auto ini = Ini.ParseString(iniString);

        enforce(ini.hasSection("main"), "Ill-formed profile file: [main] section is required");
        auto mainSec = ini.getSection("main");

        auto p = new Profile;

        if (mainSec.hasKey("name"))
        {
            p.name = mainSec.getKey("name");
        }

        enforce(mainSec.hasKey("arch"),
                "Ill-formed profile file: arch field is required in the main section");
        enforce(mainSec.hasKey("os"),
                "Ill-formed profile file: os field is required in the main section");
        enforce(mainSec.hasKey("buildtype"),
                "Ill-formed profile file: buildtype field is required in the main section");

        p.arch = fromConfig!Arch(mainSec.getKey("arch"));
        p.os = fromConfig!OS(mainSec.getKey("os"));
        p.buildType = fromConfig!BuildType(mainSec.getKey("buildtype"));

        foreach (s; ini.sections)
        {
            enum prefix = "compiler.";
            if (!s.name.startsWith(prefix))
                continue;

            const langS = s.name[prefix.length .. $];
            const lang = fromConfig!Lang(langS);

            auto c = new Compiler;
            c.lang = lang;

            if (lang in p.compilers)
                throw new Exception(
                        "Can't define more than one compiler per language and per profile");

            enforce(s.hasKey("name"),
                    "Ill-formed profile file: name field is required in the compiler sections");
            enforce(s.hasKey("version"),
                    "Ill-formed profile file: version field is required in the compiler sections");
            enforce(s.hasKey("path"),
                    "Ill-formed profile file: path field is required in the compiler sections");
            c.name = s.getKey("name");
            c.ver = s.getKey("version");
            c.path = s.getKey("path");

            p.compilers[lang] = c;
        }

        if (ini.hasSection("digest"))
        {
            enforce(ini["digest"].hasKey("hash"),
                    "Ill-formed profile file: hash field is required in the digest section");
            enforce(p.digestHash() == ini["digest"].getKey("hash"),
                    "Digest hash do not match with the one of the profile file");
        }

        return p;
    }

    /// Load a [Profile] from ini file.
    /// if ini do not have a name field, name will be assessed from the filename
    static Profile loadFromFile(string filename)
    {
        import std.file : read;
        import std.path : baseName, stripExtension;

        const ini = cast(string) read(filename);
        auto p = Profile.fromIni(ini);

        if (!p.name)
            p.name = baseName(stripExtension(filename));

        return p;
    }
}

Profile detectDefaultProfile(Lang[] langs, BuildType buildType = BuildType.release)
{
    if (!langs.length)
        throw new Exception("at least one language is needed");

    auto p = new Profile;
    p.name = "default";
    p.arch = currentArch();
    p.os = currentOS();
    p.buildType = buildType;
    foreach (l; langs)
    {
        auto comp = detectDefaultCompiler(l);
        if (comp)
            p.compilers[l] = comp;
    }

    return p;
}

private:

import dopamine.util;

import std.process;
import std.regex;

// import std.stdio;

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

shared static this()
{
    CompilerDetectF[][Lang] order;

    order[Lang.d] = [&detectDmd, &detectLdc];

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

Arch currentArch()
{
    version (X86_64)
    {
        return Arch.x86_64;
    }
    else version (X86)
    {
        return Arch.x86;
    }
    else
    {
        static assert(false, "unsupported architecture");
    }
}

OS currentOS()
{
    version (Windows)
    {
        return OS.windows;
    }
    else version (linux)
    {
        return OS.linux;
    }
    else
    {
        static assert(false, "unsupported OS");
    }
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

    auto res = new Compiler;
    res.lang = lang;
    res.name = name;
    auto ver = matchFirst(result.output, regex(re, "m"));
    if (ver.length < 2)
    {
        throw new Exception(format("Could not determine %s version. Command output:\n%s",
                name, result.output));
    }
    res.ver = ver[1];
    res.path = command[0];

    return res;

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
