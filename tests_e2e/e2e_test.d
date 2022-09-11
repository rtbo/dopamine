module e2e_test;

import e2e_assert;
import e2e_registry;
import e2e_sandbox;
import e2e_utils;

import std.exception;
import std.file;
import std.format;
import std.path;
import std.process;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;

struct Exes
{
    string client;
    string registry;
    string admin;
}

final class Test
{
    string name;
    string recipe;
    string cache;
    string registry;
    string user;

    Skip[] skips;
    CmdTest[] cmds;

    this(string filename)
    {
        const lineRe = regex(`^(EXPECT|ASSERT|SKIP)_([A-Z_]+)(\[(.*?)\])?(=(.+))?$`);

        name = baseName(stripExtension(filename));

        auto testFile = File(filename, "r");

        CmdTest cmd;

        foreach (line; testFile.byLineCopy())
        {
            line = line.strip();
            if (line.length == 0 || line.startsWith("#"))
            {
                continue;
            }

            enum cmdMark = "CMD=";
            enum recipeMark = "RECIPE=";
            enum cacheMark = "CACHE=";
            enum registryMark = "REGISTRY=";
            enum userMark = "USER=";

            const mark = line.startsWith(
                cmdMark, recipeMark, cacheMark, registryMark, userMark,
            );
            switch (mark)
            {
            case 1:
                enforce(recipe, "RECIPE is mandatory and must be specified before first CMD");
                // each time we hit CMD=, we open a new TestCmd
                if (cmd)
                    cmds ~= cmd;
                cmd = new CmdTest(line[cmdMark.length .. $]);
                break;
            case 2:
                enforce(!cmd, "RECIPE must be specified before first CMD");
                recipe = line[recipeMark.length .. $];
                break;
            case 3:
                enforce(!cmd, "CACHE must be specified before first CMD");
                cache = line[cacheMark.length .. $];
                break;
            case 4:
                enforce(!cmd, "REGISTRY must be specified before first CMD");
                registry = line[registryMark.length .. $];
                break;
            case 5:
                enforce(!cmd, "USER must be specified before first CMD");
                user = line[userMark.length .. $];
                break;
            case 0:
            default:
                auto m = matchFirst(line, lineRe);
                enforce(!m.empty, format("%s: Unrecognized entry: %s", name, line));

                const mode = m[1];
                const type = m[2];
                const arg = m[4];
                const data = m[6];

                if (mode == "SKIP")
                {
                    enforce(!cmd, "SKIP_* must be specified before first CMD");
                    switch (type)
                    {
                    case "NOPROG":
                        skips ~= new SkipNoProg(data);
                        break;
                    case "NOINET":
                        skips ~= new SkipNoInet;
                        break;
                    case "WINDOWS":
                    case "LINUX":
                    case "POSIX":
                        skips ~= new SkipOS(type);
                        break;
                    default:
                        throw new Exception("Unknown skip reason: " ~ type);
                    }
                    break;
                }

                enforce(cmd, "ASSERT|EXPECT needs a CMD entry before");

                Expect expect;
                bool status;

                switch (type)
                {
                case "FAIL":
                    enforce(cmd.expectations.length == 0, "ASSERT_FAIL or EXPECT_FAIL must be first");
                    expect = new StatusExpect(true);
                    status = true;
                    break;
                case "FILE":
                    expect = new ExpectFile(data);
                    break;
                case "DIR":
                    expect = new ExpectDir(data);
                    break;
                case "LIB":
                    expect = new ExpectLib(data, ExpectLib.Type.both);
                    break;
                case "STATIC_LIB":
                    expect = new ExpectLib(data, ExpectLib.Type.archive);
                    break;
                case "SHARED_LIB":
                    expect = new ExpectLib(data, ExpectLib.Type.dynamic);
                    break;
                case "NOT_LIB":
                    expect = new ExpectLib(data, ExpectLib.Type.both, Yes.expectNot);
                    break;
                case "NOT_STATIC_LIB":
                    expect = new ExpectLib(data, ExpectLib.Type.archive, Yes.expectNot);
                    break;
                case "NOT_SHARED_LIB":
                    expect = new ExpectLib(data, ExpectLib.Type.dynamic, Yes.expectNot);
                    break;
                case "EXE":
                    expect = new ExpectExe(data);
                    break;
                case "MATCH":
                    expect = new ExpectMatch(arg, data);
                    break;
                case "NOT_MATCH":
                    expect = new ExpectNotMatch(arg, data);
                    break;
                case "VERSION":
                    expect = new ExpectVersion(arg, data);
                    break;
                default:
                    throw new Exception("Unknown assertion: " ~ type);
                }

                if (!status && cmd.expectations.length == 0)
                    cmd.expectations ~= new StatusExpect(false);

                if (mode == "EXPECT")
                    cmd.expectations ~= expect;
                else if (mode == "ASSERT")
                    cmd.expectations ~= new Assert(expect);
                else
                    assert(false, "unknown assertion mode: " ~ mode);

                break;
            }
        }

        enforce(cmd, "At least one CMD entry is required");

        cmds ~= cmd;
    }

    string checkSkipMsg()
    {
        foreach (skip; skips)
        {
            string msg = skip.skip();
            if (msg)
                return msg;
        }
        return null;
    }

    int perform(Exes exes)
    {
        auto sandbox = new Sandbox(name);

        // clean the previous if any
        sandbox.clean();

        sandbox.prepare(this, exes);

        Registry reg;
        if (registry)
            reg = new Registry(exes, sandbox);

        int numFailed;

        try
        {
            foreach (i, cmd; cmds)
            {
                numFailed += cmd.exec(cast(int) i + 1, sandbox, gdb);
                if (numFailed)
                    break;
            }
        }
        finally
        {
            if (reg)
            {
                int code = reg.stop();
                stderr.writeln("registry exit code ", code);
                reg.reportOutput(stderr);
            }
        }

        // in case of success, we delete the sandbox dir,
        // otherwise we leave it here as it might be useful
        // to look at its content for debug

        if (numFailed == 0 && !environment.get("E2E_KEEPSANDBOX"))
            sandbox.clean();

        return numFailed;
    }
}

private class CmdTest
{
    string command;
    Expect[] expectations;

    string fileOut;
    string fileErr;

    this(string command)
    {
        this.command = command;
    }

    int exec(int id, Sandbox sandbox)
    {
        const cmd = expandEnvVars(command, sandbox.env);
        fileOut = sandbox.path(format!"%s.stdout"(id));
        fileErr = sandbox.path(format!"%s.stderr"(id));

        auto pid = spawnShell(
            cmd,
            stdin,
            File(fileOut, "w"),
            File(fileErr, "w"),
            sandbox.env,
            Config.none,
            sandbox.recipePath()
        );

        int status = pid.wait();

        if (exists(sandbox.path("build-id.hash")))
        {
            const hash = cast(string) assumeUnique(read(sandbox.path("build-id.hash")));
            sandbox.env["DOP_BID_HASH"] = hash;
            sandbox.env["DOP_BID"] = hash[0 .. 10];
        }

        auto result = RunResult(
            sandbox.name, status, fileOut, fileErr, sandbox.recipePath(), sandbox.env.dup
        );

        reportFileContent(stderr, fileOut, format!"%02s: STDOUT of %s"(id, command));
        reportFileContent(stderr, fileErr, format!"%02s: STDERR of %s"(id, command));

        int numFailed;
        foreach (exp; expectations)
        {
            const failMsg = exp.expect(result);
            if (failMsg)
            {
                stderr.writefln("%02s: ASSERTION FAILED: %s", id, failMsg);
                numFailed++;
                if (cast(Assert) exp)
                    break;
            }
        }

        return numFailed;
    }
}
