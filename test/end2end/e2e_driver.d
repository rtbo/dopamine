/// Driver for end to end tests
///
/// Read one *.test file, run the provided command and perform the associated assertions
module e2e_driver;

import std.array;
import std.exception;
import std.file;
import std.path;
import std.process;
import std.regex;
import std.stdio;
import std.string;

interface Expect
{
    // return error message on failure
    string expect(ref RunResult res);
}

class StatusExpect : Expect
{
    bool expectFail;

    string expect(ref RunResult res)
    {
        const fail = res.status != 0;
        if (fail == expectFail)
        {
            return null;
        }

        if (expectFail)
        {
            return "Expected command failure";
        }

        return format("Command failed with status %s", res.status);
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

    bool hasMatch(File file)
    {
        import std.typecons : No;

        auto re = regex(rexp);

        foreach (line; file.byLine(No.keepTerminator))
        {
            if (line.matchFirst(re))
            {
                return true;
            }
        }
        return false;
    }

    override string expect(ref RunResult res)
    {
        if (hasMatch(res.file(filename)))
        {
            return null;
        }

        return format("Expected to match %s in %s", rexp, filename);
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
        if (!hasMatch(res.file(filename)))
        {
            return null;
        }

        return format("Unexpected match %s in %s", rexp, filename);
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
        if (exists(path) && isFile(path)) {
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
        if (exists(path) && isDir(path)) {
            return null;
        }

        return "No such directory: " ~ path;
    }
}

struct Test
{
    string name;
    string command;
    string recipeDir;
    string homeDir;

    Expect[] expectations;

    static Test parseFile(string filename)
    {
        const expectRe = regex(`^EXPECT_([A-Z_]+)(\[(.*?)\])?(=(.+))?$`);

        Test test;
        test.name = baseName(stripExtension(filename));

        auto testFile = File(filename, "r");
        auto statusExpect = new StatusExpect;
        test.expectations ~= statusExpect;

        foreach (line; testFile.byLineCopy())
        {
            line = line.strip();
            if (line.length == 0 || line.startsWith("#"))
            {
                continue;
            }
            else if (line.startsWith("CMD="))
            {
                test.command = line[4 .. $];
            }
            else if (line.startsWith("RECIPE="))
            {
                test.recipeDir = line[7 .. $];
            }
            else if (line.startsWith("HOME="))
            {
                test.homeDir = line[5 .. $];
            }
            else
            {
                auto m = matchFirst(line, expectRe);
                enforce(!m.empty, format("%s: Unrecognized entry: %s", test.name, line));

                const type = m[1];
                const file = m[3];
                const data = m[5];

                switch (type)
                {
                case "FAIL":
                    statusExpect.expectFail = true;
                    break;
                case "MATCH":
                    auto exp = new ExpectMatch(file, data);
                    test.expectations ~= exp;
                    break;
                case "NOT_MATCH":
                    auto exp = new ExpectNotMatch(file, data);
                    test.expectations ~= exp;
                    break;
                case "FILE":
                    test.expectations ~= new ExpectFile(data);
                    break;
                case "DIR":
                    test.expectations ~= new ExpectDir(data);
                    break;
                default:
                    throw new Exception("Unknown assertion: " ~ type);
                }
            }
        }

        if (!test.homeDir)
        {
            test.homeDir = "empty";
        }

        return test;
    }

    void checkDir(string dir)
    {
        enforce(exists(dir) && isDir(dir), format("%s: no such directory: %s", name, dir));
    }

    void check()
    {
        enforce(command, format("%s: CMD must be provided", name));
        enforce(recipeDir, format("%s: RECIPE must be provided", name));

        checkDir(e2ePath("recipes", recipeDir));
        checkDir(e2ePath("homes", homeDir));
    }

    string sandboxPath(Args...)(Args args)
    {
        return e2ePath("sandbox", name, args);
    }

    string sandboxRecipePath(Args...)(Args args)
    {
        return sandboxPath("recipe", args);
    }

    string sandboxHomePath(Args...)(Args args)
    {
        return sandboxPath("home", args);
    }

    void prepareSandbox()
    {
        copyContentToSandbox(e2ePath("recipes", recipeDir), sandboxRecipePath());
        copyContentToSandbox(e2ePath("homes", homeDir), sandboxHomePath());
    }

    void copyContentToSandbox(string src, string sandbox)
    {
        mkdirRecurse(sandbox);

        foreach (entry; dirEntries(src, SpanMode.breadth))
        {
            string radical = relativePath(entry.name, src);
            string dest = buildPath(sandbox, radical);

            if (entry.isDir)
            {
                mkdirRecurse(dest);
            }
            else
            {
                copy(entry.name, dest);
            }
        }
    }

    string[string] makeSandboxEnv(string dopExe)
    {
        string[string] env;
        env["DOP"] = dopExe;
        env["DOP_HOME"] = sandboxHomePath();
        return env;
    }

    int perform(string dopExe)
    {
        auto env = makeSandboxEnv(dopExe);

        mkdirRecurse(sandboxPath());
        scope (exit)
            rmdirRecurse(sandboxPath());

        prepareSandbox();

        const cmd = expandEnvVars(command, env);

        const outPath = sandboxPath("stdout");
        const errPath = sandboxPath("stderr");

        // FIXME: we'd better have a command parser that return an array of args
        // in platform independent way instead of relying on native shell.
        // This would allow portable CMD in test files.

        auto pid = spawnShell(
            cmd, stdin, File(outPath, "w"), File(errPath, "w"),
            env, Config.none, sandboxRecipePath
        );

        int status = pid.wait();

        auto result = RunResult(
            name, status, outPath, errPath, sandboxRecipePath, env
        );

        bool outputShown;
        int numFailed;

        foreach (exp; expectations)
        {
            const failMsg = exp.expect(result);
            if (failMsg)
            {
                if (!outputShown)
                {
                    import std.typecons : Yes;

                    stderr.writefln("TEST %s", name);
                    stderr.writefln("Command: %s", cmd);
                    stderr.writefln("Return status: %s", status);
                    stderr.writeln("STDOUT ------");
                    foreach (l; File(outPath, "r").byLine(Yes.keepTerminator))
                    {
                        stderr.write(l);
                    }
                    stderr.writeln("-------------");
                    stderr.writeln("STDERR ------");
                    foreach (l; File(errPath, "r").byLine(Yes.keepTerminator))
                    {
                        stderr.write(l);
                    }
                    stderr.writeln("-------------");
                }
                stderr.writeln("ASSERTION FAILED: ", failMsg);
                numFailed++;
            }
        }

        return numFailed;
    }
}

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
        return absolutePath(expandEnvVars(name, env));
    }

    File file(string name)
    {
        return File(filepath(name), "r");
    }
}


string e2ePath(Args...)(
    Args args)
{
    return buildNormalizedPath(dirName(__FILE_FULL_PATH__), args);
}

// expand env vars of shape $VAR or ${VAR}
string expandEnvVars(string input, string[string] environment)
{
    import std.algorithm : canFind;
    import std.ascii : isAlphaNum;

    string result;

    string var;
    bool env;
    bool mustach;

    void expand()
    {
        const val = var in environment;
        enforce(val, "Could not find %s in sandbox environment");
        result ~= *val;
        var = null;
        env = false;
        mustach = false;
    }

    foreach (dchar c; input)
    {
        if (env && !mustach)
        {
            if (isAlphaNum(c))
                var ~= c;
            else if (var.length == 0 && c == '{')
                mustach = true;
            else
            {
                expand();
                result ~= c;
            }
        }
        else if (env && mustach)
        {
            if (c == '}')
                expand();
            else
                var ~= c;
        }
        else if (c == '$')
        {
            env = true;
        }
        else
        {
            result ~= c;
        }
    }

    if (env)
    {
        throw new Exception(
            "Unterminated environment variable");
    }

    return result;
}

int usage(string[] args, int code)
{
    stderr.writefln("Usage: %s [TEST_FILE]", args[0]);
    return code;
}

int main(string[] args)
{
    if (args.length < 2)
    {
        stderr.writeln(
            "Error: missing test file");
        return usage(args, 1);
    }
    if (!exists(args[1]))
    {
        stderr.writefln("Error: No such file: %s", args[1]);
        return usage(args, 1);
    }

    const dopExe = absolutePath(
        environment["DOP"]);

    try
    {
        auto test = Test.parseFile(
            args[1]);
        test.check();
        return test.perform(dopExe);
    }
    catch (Exception ex)
    {
        stderr.writeln(ex.msg);
        if (environment.get("E2E_STACKTRACE"))
        {
            stderr.writeln(
                "Driver stack trace:");
            stderr.writeln(
                ex.info);
        }
        return 1;
    }
}
