module e2e_driver;

import std.file;
import std.path;
import std.process;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;

struct Test
{
    string cmd;
    string dir;
    bool expectFail;
    string[] expectedOutputs;
}

string e2eDir()
{
    return buildNormalizedPath(dirName(__FILE_FULL_PATH__));
}

string getLocalPath(string path)
{
    return isAbsolute(path) ? buildNormalizedPath(path) : buildNormalizedPath(getcwd(), path);
}

int main(string[] args)
{
    if (args.length < 2 || !exists(args[1]))
    {
        stderr.writefln("Usage: %s [TEST_FILE]", args[0]);
        return -1;
    }

    const dopExe = getLocalPath(environment["DOP"]);
    const testFileName = getLocalPath(args[1]);
    const testName = baseName(stripExtension(testFileName));

    auto testFile = File(testFileName, "r");

    Test test;

    foreach (line; testFile.byLineCopy(No.keepTerminator))
    {
        line = line.strip();

        if (line.startsWith("#"))
        {
            continue;
        }
        else if (line.startsWith("CMD="))
        {
            test.cmd = line[4 .. $];
        }
        else if (line.startsWith("DIR="))
        {
            test.dir = line[4 .. $];
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
            stderr.writeln("Unrecognized test input: ", line);
            return -2;
        }
    }

    testFile.close();

    if (!test.cmd)
    {
        stderr.writefln("No command provided in  %s", testFileName);
        return -2;
    }

    if (test.dir)
    {
        const dir = buildNormalizedPath(e2eDir, test.dir);
        if (!exists(dir) || !isDir(dir))
        {
            stderr.writefln("No such directory: %s", dir);
            return -3;
        }
        chdir(dir);
    }

    const quotDop = format(`"%s"`, dopExe);
    auto cmd = test.cmd
        .replace("\"$DOP\"", quotDop)
        .replace("$DOP", quotDop);
    auto result = executeShell(cmd);

    const fail = result.status != 0;

    if (test.expectFail != fail)
    {
        if (test.expectFail)
        {
            stderr.writefln("%s expected to fail but succeeded", testName);
        }
        else
        {
            stderr.writefln("%s expected to succeed but failed", testName);
        }
        stderr.writeln("Output:");
        stderr.writeln(result.output);
        return 1;
    }

    int failures;
    bool outputShown;

    foreach (exp; test.expectedOutputs)
    {
        auto res = matchFirst(result.output, exp);
        if (res.empty)
        {
            if (!outputShown)
            {
                stderr.writefln("command: %s\noutput:\n%s\n--------", test.cmd, result.output);
                outputShown = true;
            }
            stderr.writefln("Could not match %s", exp);
            failures += 1;
        }
    }

    return failures;
}
