module dopamine.pkgconf;

import std.exception;
import std.range;
import std.stdio;
import std.string;

struct PkgConfFile
{
    struct Var
    {
        string name;
        string value;
    }

    Var[] vars;

    string name;
    string ver;
    string description;
    string url;
    string license;
    string maintainer;
    string copyright;

    string[] cflags;
    string[] cflagsPriv;
    string[] libs;
    string[] libsPriv;
    string[] required;
    string[] requiredPriv;
    string[] conflicts;
    string[] provided;

    static PkgConfFile parseFile(const(char)[] filename)
    {
        auto f = File(filename, "r");

        PkgConfFile res;

        char[8192] buf;
        while(true)
        {
            char* cline = pkgconf_fgetline(&buf[0], buf.length, f.getFP());
            if (!cline)
                break;

            const(char)[] line = cline.fromStringz();
            line = line.strip();
            if (line.length)
                parsePkgConfLine(line.idup, res);
        }

        return res;
    }

    string var(string name)
    {
        foreach (v; vars)
        {
            if (v.name == name)
                return v.value;
        }
        throw new Exception("Unknown variable: " ~ name);
    }

    bool setVar(string name, string value)
    {
        foreach (ref v; vars)
        {
            if (v.name == name)
            {
                v.value = value;
                return false;
            }
        }
        vars ~= Var(name, value);
        return true;
    }

    void write(O)(O output) if (isOutputRange!(O, char))
    {
        foreach (v; vars)
        {
            output.put(v.name ~ "=" ~ v.value ~ "\n");
        }
        output.put("\n");
        output.put("Name: " ~ enforce(name, "Name field is required") ~ "\n");
        output.put("Version: " ~ enforce(ver, "Version field is required") ~ "\n");
        if (description)
            output.put("Description: " ~ description ~ "\n");
        if (url)
            output.put("URL: " ~ url ~ "\n");
        if (license)
            output.put("License: " ~ license ~ "\n");
        if (maintainer)
            output.put("Maintainer: " ~ maintainer ~ "\n");
        if (copyright)
            output.put("Copyright: " ~ copyright ~ "\n");
        if (cflags)
            output.put("Cflags: " ~ cflags.join(" ") ~ "\n");
        if (cflagsPriv)
            output.put("Cflags.private: " ~ cflagsPriv.join(" ") ~ "\n");
        if (libs)
            output.put("Libs: " ~ libs.join(" ") ~ "\n");
        if (libsPriv)
            output.put("Libs.private: " ~ libsPriv.join(" ") ~ "\n");
        if (required)
            output.put("Requires: " ~ required.join(" , ") ~ "\n");
        if (requiredPriv)
            output.put("Requires.private: " ~ requiredPriv.join(" , ") ~ "\n");
        if (conflicts)
            output.put("Conflicts: " ~ conflicts.join(" , ") ~ "\n");
        if (provided)
            output.put("Provides: " ~ provided.join(" , ") ~ "\n");
    }
}

private:

void parsePkgConfLine(string line, ref PkgConfFile pcf)
{
    size_t idx;
    while(idx < line.length)
    {
        const char c = line[idx];
        if (c == '=')
        {
            enforce(idx > 0, "Invalid empty variable name");
            string ident = line[0 .. idx];
            string val = line[idx+1 .. $].strip();
            pcf.vars ~= PkgConfFile.Var(ident, val);
            break;
        }
        else if (c == ':')
        {
            enforce(idx > 0, "Invalid empty keyword");
            string ident = line[0 .. idx];
            string val = line[idx+1 .. $].strip();
            switch (ident)
            {
            case "Name":
                pcf.name = val;
                break;
            case "Version":
                pcf.ver = val;
                break;
            case "Description":
                pcf.description = val;
                break;
            case "URL":
                pcf.url = val;
                break;
            case "License":
                pcf.license = val;
                break;
            case "Maintainer":
                pcf.maintainer = val;
                break;
            case "Copyright":
                pcf.ver = val;
                break;
            case "Cflags":
            case "CFLAGS":
                pcf.cflags = argvSplit(val);
                break;
            case "Cflags.private":
            case "CFLAGS.private":
                pcf.cflagsPriv = argvSplit(val);
                break;
            case "Libs":
            case "LIBS":
                pcf.libs = argvSplit(val);
                break;
            case "Libs.private":
            case "LIBS.private":
                pcf.libsPriv = argvSplit(val);
                break;
            case "Requires":
                pcf.required = depsSplit(val);
                break;
            case "Requires.private":
                pcf.requiredPriv = depsSplit(val);
                break;
            case "Conflicts":
                pcf.conflicts = depsSplit(val);
                break;
            case "Provides":
                pcf.provided = depsSplit(val);
                break;
            default:
                throw new Exception("Unknown pkg-config keyword: " ~ ident);
            }
            break;
        }
        else
        {
            idx++;
        }
    }
}

string[] argvSplit(string src)
{
    auto csrc = toStringz(src);
    int argc;
    char **argv;

    if (pkgconf_argv_split(csrc, &argc, &argv) != 0)
        throw new Exception("Failed to split args from Pkg-config file: `" ~ src ~ "`");

    string[] res = new string[argc];
    for(int idx; idx < argc; ++idx)
    {
        res[idx] = fromStringz(argv[idx]).idup;
    }
    pkgconf_argv_free(argv);
    return res;
}

string[] depsSplit(string src)
{
    auto deps = src.split(",");
    foreach (ref dep; deps)
        dep = dep.strip();
    return deps;
}

// a few functions from pkgconf are used.
extern(C) nothrow char *pkgconf_fgetline(char *line, size_t size, FILE *stream);
extern(C) nothrow int pkgconf_argv_split(const char *src, int *argc, char ***argv);
extern(C) nothrow void pkgconf_argv_free(char **argv);

version(unittest)
{
    import test.util;
    import unit_threaded.assertions;
}

@("PkgConfFile")
unittest
{
    import std.file;

    // parsing
    auto pc = `
prefix=/some/path
# a comment
incdir=${prefix}/include
libdir=${prefix}/lib

Name: package name
Version: 1.0.0
URL: https://pkg.com
Cflags: -I${incdir} -Wall
Libs: -lpkg -L${libdir}
    `;

    auto dm = DeleteMe("pkg", ".pc");
    std.file.write(dm.path, pc);

    auto pkgf = PkgConfFile.parseFile(dm.path);

    pkgf.vars.should == [
        PkgConfFile.Var("prefix", "/some/path"),
        PkgConfFile.Var("incdir", "${prefix}/include"),
        PkgConfFile.Var("libdir", "${prefix}/lib"),
    ];

    pkgf.var("incdir").should == "${prefix}/include";

    pkgf.name.should == "package name";
    pkgf.ver.should == "1.0.0";
    pkgf.url.should == "https://pkg.com";
    pkgf.libs.should == [ "-lpkg", "-L${libdir}" ];
    pkgf.cflags.should == [ "-I${incdir}", "-Wall" ];

    // modification
    pkgf.setVar("prefix", "/some/other/path");

    auto expected = `
prefix=/some/other/path
incdir=${prefix}/include
libdir=${prefix}/lib

Name: package name
Version: 1.0.0
URL: https://pkg.com
Cflags: -I${incdir} -Wall
Libs: -lpkg -L${libdir}
    `;

    auto output = appender!string();
    pkgf.write(output);
    output.data.strip().should == expected.strip();
}
