module e2e_main;

import e2e_utils;
import e2e_test;

import std.file;
import std.path;
import std.process;
import std.stdio;

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

    const exes = Exes(
        absolutePath(environment["DOP"]),
        absolutePath(environment["DOP_SERVER"]),
        absolutePath(environment["DOP_ADMIN"]),
    );

    try
    {
        auto test = new Test(args[1]);
        string skipMsg = test.checkSkipMsg();
        if (skipMsg)
        {
            stderr.writeln("SKIP: ", skipMsg);
            return 77; // GNU skip return code
        }

        return test.perform(exes);
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
