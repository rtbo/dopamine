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
    string directory;

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
            else if (line.startsWith("DIR="))
            {
                test.directory = line[4 .. $];
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

        return test;
    }

    void check()
    {
        enforce(command, format("%s: CMD must be provided", name));
        enforce(directory, format("%s: DIR must be provided", name));
    }

    File lockSandbox()
    {
        string path = sandboxPath(setExtension(directory, "lock"));
        mkdirRecurse(dirName(path));
        auto lock = File(path, "w");
        lock.lock();
        return lock;
    }

    void prepareSandbox()
    {
        string e2e = e2ePath();

        foreach (entry; dirEntries(e2ePath(directory), SpanMode.breadth))
        {
            string radical = relativePath(entry.name, e2e);
            string dest = sandboxPath(radical);

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

    void perform(string dopExe)
    {
        chdir(sandboxPath(directory));

        const quotDop = format(`"%s"`, dopExe);
        auto cmd = this.command
            .replace("\"$DOP\"", quotDop)
            .replace("$DOP", quotDop);

        auto result = executeShell(cmd);

        const fail = result.status != 0;

        if (expectFail != fail)
        {
            Appender!string app;
            if (expectFail)
            {
                app.put(format("%s: expected to fail but succeeded\n", name));
            }
            else
            {
                app.put(format("%s: command failed with status %s\n", name, result.status));
            }
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

    void cleanup()
    {
        rmdirRecurse(sandboxPath(directory));
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

        File lock = test.lockSandbox();
        scope (exit)
            lock.close();

        test.prepareSandbox();
        test.perform(dopExe);

        test.cleanup();
    }
    catch (Exception ex)
    {
        stderr.writeln(ex.msg);
        return 1;
    }

    return 0;

}

string e2ePath(Args...)(Args args)
{
    return buildNormalizedPath(dirName(__FILE_FULL_PATH__), args);
}

string sandboxPath(Args...)(Args args)
{
    return e2ePath("sandbox", args);
}
