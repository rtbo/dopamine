module e2e_driver;

import std.exception;
import std.file;
import std.path;
import std.process;
import std.regex;
import std.stdio;
import std.string;

struct Test
{
    string name;
    string command;
    string directory;
    bool expectFail;
    string[] expectedOutputs;

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
            else if (line.startsWith("EXPECT_OUTPUT="))
            {
                enum len = "EXPECT_OUTPUT=".length;
                test.expectedOutputs ~= line[len .. $];
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
        import std.array : Appender;

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

        foreach (exp; expectedOutputs)
        {
            auto res = matchFirst(result.output, exp);
            if (res.empty)
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
                failureMsg.put(format("Could not match %s", exp));
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

int main(string[] args)
{
    if (args.length < 2 || !exists(args[1]))
    {
        stderr.writefln("Usage: %s [TEST_FILE]", args[0]);
        return -1;
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
