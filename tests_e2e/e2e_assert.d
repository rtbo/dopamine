module e2e_assert;

import e2e_utils;

import std.file;
import std.format;
import std.path;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;

struct RunResult
{
    string name;
    int status;
    string stdout;
    string stderr;

    string cwd;
    string[string] env;

    string filepath(string name)
    {
        if (name == "stdout")
        {
            return stdout;
        }
        if (name == "stderr")
        {
            return stderr;
        }
        return absolutePath(expandEnvVars(name, env), cwd);
    }

    File file(string name)
    {
        return File(filepath(name), "r");
    }
}

interface Expect
{
    // return error message on failure
    string expect(ref RunResult res);
}

class Assert : Expect
{
    Expect exp;
    this(Expect exp)
    {
        this.exp = exp;
    }

    override string expect(ref RunResult res)
    {
        return exp.expect(res);
    }
}

class StatusExpect : Expect
{
    bool expectFail;

    this(bool expectFail = false)
    {
        this.expectFail = expectFail;
    }

    override string expect(ref RunResult res)
    {
        const fail = res.status != 0;
        if (fail == expectFail)
        {
            return null;
        }

        if (expectFail)
        {
            return "Command returned 0 but expected failure";
        }

        return format("Command failed with status %s", res.status);
    }
}

class ExpectFile : Expect
{
    string filename;

    this(string filename)
    {
        this.filename = filename;
    }

    override string expect(ref RunResult res)
    {
        const path = res.filepath(filename);
        if (exists(path) && isFile(path))
        {
            return null;
        }

        return "No such file: " ~ path;
    }
}

class ExpectDir : Expect
{
    string filename;

    this(string filename)
    {
        this.filename = filename;
    }

    override string expect(ref RunResult res)
    {
        const path = res.filepath(filename);
        if (exists(path) && isDir(path))
        {
            return null;
        }

        return "No such directory: " ~ path;
    }
}

class ExpectLib : Expect
{
    enum Type
    {
        archive = 1,
        dynamic = 2,
        both = 3,
    }

    string dirname;
    string basename;
    Type type;
    Flag!"expectNot" expectNot;

    this(string path, Type type, Flag!"expectNot" expectNot = No.expectNot)
    {
        dirname = dirName(path);
        basename = baseName(path);
        this.type = type;
        this.expectNot = expectNot;
    }

    override string expect(ref RunResult res)
    {
        const dirname = res.filepath(this.dirname);

        string[] names;
        if (type & Type.archive)
        {
            names ~= [
                "lib" ~ basename ~ ".a",
                basename ~ "d.lib", // debug version on windows
                basename ~ ".lib",
            ];
        }
        if (type & Type.dynamic)
        {
            names ~= [
                "lib" ~ basename ~ ".so",
                basename ~ "d.dll", // debug version on windows
                basename ~ ".dll",
            ];
        }
        string found;
        string[] tries;
        foreach (name; names)
        {
            const path = buildPath(dirname, name);
            if (exists(path))
            {
                found = path;
                break;
            }
            else
            {
                tries ~= path;
            }
        }

        if (expectNot)
        {
            if (!found)
                return null;
            else
                return format!"Did not expect to find library %s (%s)"(basename, found);
        }

        if (found)
            return null;

        auto msg = format("Could not find any library named %s in %s\nTried:", basename, dirname);
        foreach (tr; tries)
        {
            msg ~= "\n - " ~ tr;
        }
        if (msg && expectNot)
            msg = null;
        return msg;
    }
}

class ExpectExe : Expect
{
    string path;

    this(string path)
    {
        version (Windows)
        {
            if (!path.endsWith(".exe"))
            {
                path ~= ".exe";
            }
        }
        this.path = path;
    }

    override string expect(ref RunResult res)
    {
        const path = res.filepath(this.path);
        if (exists(path))
            return null;
        return format("Could not find the expected executable %s", path);
    }
}

class ExpectMatch : Expect
{
    string filename;
    string rexp;

    this(string filename, string rexp)
    {
        this.filename = filename ? filename : "stdout";
        this.rexp = rexp;
    }

    bool hasMatch(string file)
    {
        const content = cast(string) read(file);
        auto re = regex(rexp, "m");
        return cast(bool) content.matchFirst(re);
    }

    override string expect(ref RunResult res)
    {
        if (hasMatch(res.filepath(filename)))
        {
            return null;
        }

        return format("Expected to match '%s' in '%s'", rexp, filename);
    }
}

class ExpectNotMatch : ExpectMatch
{
    this(string filename, string rexp)
    {
        super(filename, rexp);
    }

    override string expect(ref RunResult res)
    {
        if (!hasMatch(res.filepath(filename)))
        {
            return null;
        }

        return format("Unexpected match '%s' in '%s'", rexp, filename);
    }
}

class ExpectVersion : Expect
{
    string pkgname;
    string ver;

    this(string pkgname, string ver)
    {
        this.pkgname = pkgname;
        this.ver = ver;
    }

    override string expect(ref RunResult res)
    {
        import vibe.data.json : parseJsonString;

        auto lockpath = res.filepath("dop.lock");
        auto jsonStr = cast(string) read(lockpath);
        auto json = parseJsonString(jsonStr);
        foreach (jpack; json["packages"])
        {
            if (jpack["name"] != pkgname)
                continue;

            foreach (jver; jpack["versions"])
            {
                if (jver["status"] == "resolved")
                {
                    if (jver["version"] == ver)
                    {
                        return null;
                    }
                    else
                    {
                        return format(
                            "%s was resolved to v%s (expected v%s)",
                            pkgname, jver["version"].get!string, ver
                        );
                    }
                }
            }
            return "could not find a resolved version for " ~ pkgname;
        }
        return "could not find package " ~ pkgname ~ " in dop.lock";
    }
}

interface Skip
{
    string skip();
}

class SkipOS : Skip
{
    string os;

    this(string os)
    {
        this.os = os;
    }

    override string skip()
    {
        version (Windows)
        {
            const skp = os.toLower() == "windows";
        }
        else version (linux)
        {
            const skp = os.toLower() == "linux" || os.toLower() == "posix";
        }
        else version (Posix)
        {
            const skp = os.toLower() == "posix";
        }
        if (skp)
        {
            return os[0 .. 1].toUpper() ~ os[1 .. $].toLower();
        }
        return null;
    }
}

class SkipNoProg : Skip
{
    string progname;

    this(string progname)
    {
        this.progname = progname;
    }

    override string skip()
    {
        import std.process : environment;

        string prog = progname;
        version (Windows)
        {
            if (!prog.endsWith(".exe"))
                prog ~= ".exe";
        }
        if (!searchInEnvPath(environment["PATH"], prog))
        {
            return format("%s: No such program in PATH", progname);
        }
        return null;
    }
}

class SkipNoInet : Skip
{
    override string skip()
    {
        import core.time : seconds;
        import vibe.http.client : HTTPClientSettings, requestHTTP;

        const checkUrl = "http://clients3.google.com/generate_204";
        auto settings = new HTTPClientSettings;
        settings.connectTimeout = 5.seconds;
        settings.defaultKeepAliveTimeout = 0.seconds;

        try
        {
            int statusCode;

            requestHTTP(
                checkUrl,
                (scope req) {},
                (scope res) { statusCode = res.statusCode; },
                settings
            );

            if (statusCode == 204)
                return null;
        }
        catch (Exception ex)
        {
            writeln(ex.msg);
        }

        return "Can't establish internet connection (or clients3.google.com is down)";
    }
}
