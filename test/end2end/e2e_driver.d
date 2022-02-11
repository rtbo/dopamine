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
    bool expect(ref Test test, string output);
    string failMsg();
}

class ExpectMatch : Expect
{
    string exp;

    this(string exp)
    {
        this.exp = exp;
    }

    bool expect(ref Test test, string output)
    {
        auto res = matchFirst(output, exp);
        return !res.empty;
    }

    string failMsg()
    {
        return format("Expected to match %s", exp);
    }
}

class ExpectNotMatch : Expect
{
    string exp;

    this(string exp)
    {
        this.exp = exp;
    }

    bool expect(ref Test test, string output)
    {
        auto res = matchFirst(output, exp);
        return res.empty;
    }

    string failMsg()
    {
        return format("Unexpected match %s", exp);
    }
}

struct Test
{
    string name;
    string command;
    string recipeDir;
    string homeDir;

    bool expectFail;

    Expect[] expectations;

    static Test parseFile(string filename)
    {
        import std.typecons : No;

        Test test;
        test.name = baseName(stripExtension(filename));

        auto testFile = File(filename, "r");

        foreach (line; testFile.byLineCopy(No.keepTerminator))
        {
            line = line.strip();

            if (line.startsWith("#"))
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
            else if (line == "EXPECT_FAIL")
            {
                test.expectFail = true;
            }
            else if (line.startsWith("EXPECT_MATCH="))
            {
                enum len = "EXPECT_MATCH=".length;
                test.expectations ~= new ExpectMatch(line[len .. $]);
            }
            else if (line.startsWith("EXPECT_NOT_MATCH="))
            {
                enum len = "EXPECT_NOT_MATCH=".length;
                test.expectations ~= new ExpectNotMatch(line[len .. $]);
            }
            else
            {
                throw new Exception(format("%s: Unrecognized input: %s", test.name, line));
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

    void perform(string dopExe)
    {

        auto env = makeSandboxEnv(dopExe);

        mkdirRecurse(sandboxPath());
        scope (exit)
            rmdirRecurse(sandboxPath());

        prepareSandbox();

        const cmd = expandEnvVars(command, env);

        // FIXME: we'd better have a command parser that return an array of args
        // in platform independent way instead of relying on native shell.
        // This would allow portable CMD in test files.
        auto result = executeShell(cmd, env, Config.none, size_t.max, sandboxRecipePath());

        const fail = result.status != 0;

        if (expectFail != fail)
        {
            Appender!string app;
            if (!expectFail)
            {
                app.put(format("%s: command failed with status %s\n", name, result.status));
            }
            else
            {
                app.put(format("%s: expected to fail but succeeded\n", name));
            }
            app.put(format("Command: %s\n", cmd));
            app.put("Output:\n");
            app.put(result.output);
            throw new Exception(app.data);
        }

        Appender!string failureMsg;
        bool outputAdded;

        foreach (exp; expectations)
        {
            if (!exp.expect(this, result.output))
            {
                if (!outputAdded)
                {
                    auto lineSplit = result.output.endsWith("\n") ? "" : "\n";
                    failureMsg.put(format("%s FAILURE\n", name));
                    failureMsg.put(format("command: %s\n", cmd));
                    failureMsg.put("output:\n");
                    failureMsg.put("-------\n");
                    failureMsg.put(format("%s%s", result.output, lineSplit));
                    failureMsg.put("-------\n");
                    outputAdded = true;
                }
                failureMsg.put(exp.failMsg);
            }
        }

        if (failureMsg.data.length)
        {
            throw new Exception(failureMsg.data);
        }
    }
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
        stderr.writeln("Error: missing test file");
        return usage(args, 1);
    }
    if (!exists(args[1]))
    {
        stderr.writefln("Error: No such file: %s", args[1]);
        return usage(args, 1);
    }

    const dopExe = absolutePath(environment["DOP"]);

    try
    {
        auto test = Test.parseFile(args[1]);
        test.check();
        test.perform(dopExe);
    }
    catch (Exception ex)
    {
        stderr.writeln(ex.msg);
        stderr.writeln("Driver stack trace:");
        stderr.writeln(ex.info);
        return 1;
    }

    return 0;
}

string e2ePath(Args...)(Args args)
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
        throw new Exception("Unterminated environment variable");
    }

    return result;
}
