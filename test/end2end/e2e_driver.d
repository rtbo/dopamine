/// Driver for end to end tests
///
/// Read one *.test file, run the provided command and perform the associated assertions
module e2e_driver;

import std.array;
import std.exception;
import std.file;
import std.json;
import std.path;
import std.process;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;

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

struct Test
{
    string name;
    string command;

    string recipe;
    string cache;
    string registry;

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

            enum cmdMark = "CMD=";
            enum recipeMark = "RECIPE=";
            enum cacheMark = "CACHE=";
            enum registryMark = "REGISTRY=";

            const mark = line.startsWith(
                cmdMark, recipeMark, cacheMark, registryMark
            );
            switch (mark)
            {
            case 1:
                test.command = line[cmdMark.length .. $];
                break;
            case 2:
                test.recipe = line[recipeMark.length .. $];
                break;
            case 3:
                test.cache = line[cacheMark.length .. $];
                break;
            case 4:
                test.registry = line[registryMark.length .. $];
                break;
            case 0:
            default:
                auto m = matchFirst(line, expectRe);
                enforce(!m.empty, format("%s: Unrecognized entry: %s", test.name, line));

                const type = m[1];
                const arg = m[3];
                const data = m[5];

                switch (type)
                {
                case "FAIL":
                    statusExpect.expectFail = true;
                    break;
                case "FILE":
                    test.expectations ~= new ExpectFile(data);
                    break;
                case "DIR":
                    test.expectations ~= new ExpectDir(data);
                    break;
                case "MATCH":
                    auto exp = new ExpectMatch(arg, data);
                    test.expectations ~= exp;
                    break;
                case "NOT_MATCH":
                    auto exp = new ExpectNotMatch(arg, data);
                    test.expectations ~= exp;
                    break;
                case "VERSION":
                    auto exp = new ExpectVersion(arg, data);
                    test.expectations ~= exp;
                    break;
                default:
                    throw new Exception("Unknown assertion: " ~ type);
                }
                break;
            }
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
        enforce(recipe, format("%s: RECIPE must be provided", name));
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

    string sandboxRegistryPath(Args...)(Args args)
    {
        return sandboxPath("registry", args);
    }

    void prepareSandbox()
    {
        import std.algorithm : each, map;

        auto defs = parseJSON(cast(string) read(e2ePath("definitions.json")));

        if (registry)
        {
            defs["registries"][registry].array
                .map!(jv => jv.str)
                .each!((p) {
                    const src = e2ePath("registry", p);
                    const dest = sandboxRegistryPath(p);
                    copyRecurse(src, dest);
                });
        }

        mkdirRecurse(sandboxHomePath("cache"));
        if (cache)
        {
            defs["caches"][cache].array
                .map!(jv => jv.str)
                .each!((p) {
                    const src = e2ePath("registry", p);
                    const dest = sandboxHomePath("cache", p);
                    copyRecurse(src, dest);
                });
        }

        writefln("copy %s to %s", e2ePath("recipes", recipe), sandboxRecipePath);
        copyRecurse(e2ePath("recipes", recipe), sandboxRecipePath);
    }

    string[string] makeSandboxEnv(string dopExe)
    {
        string[string] env;
        env["DOP"] = dopExe;
        env["DOP_HOME"] = sandboxHomePath();
        return env;
    }

    // with all end-to-end tests run in //, it is necessary
    // to obtain a unique port for each instance
    Tuple!(File, int) acquireRegistryPort()
    {
        int port = 3002;
        while (1)
        {
            auto fn = e2ePath("sandbox", format("%d.lock", port));
            auto f = File(fn, "w");
            if (f.tryLock())
            {
                return tuple(f, port);
            }
            port += 1;
        }
    }

    int perform(string dopExe, string regExe)
    {
        // we delete previous sandbox if any
        const sbDir = sandboxPath();
        if (exists(sbDir) && isDir(sbDir))
            rmdirRecurse(sbDir);

        // create the sandbox dir
        mkdirRecurse(sbDir);

        prepareSandbox();

        auto env = makeSandboxEnv(dopExe);

        File portLock;
        Registry reg;

        if (registry)
        {
            import std.conv : to;

            auto res = acquireRegistryPort();
            portLock = res[0];
            const port = res[1];

            env["E2E_REGISTRY_PORT"] = port.to!string;
            env["DOP_REGISTRY"] = format("http://localhost:%s", port);
            reg = new Registry(regExe, port, env, name);
        }

        const cmd = expandEnvVars(command, env);

        const outPath = sandboxPath("stdout");
        const errPath = sandboxPath("stderr");

        // FIXME: we'd better have a command parser that return an array of args
        // in platform independent way instead of relying on native shell.
        // This would allow portable CMD in test files.

        writeln("will spawn in ", sandboxRecipePath);

        auto pid = spawnShell(
            cmd, stdin, File(outPath, "w"), File(errPath, "w"),
            env, Config.none, sandboxRecipePath
        );

        int status = pid.wait();

        if (reg)
        {
            assert(reg.stop() == 0, "registry did not close normally");
        }

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
                    stderr.writefln("TEST:     %s", name);
                    stderr.writefln("RECIPE:   %s", recipe);
                    stderr.writefln("CACHE:    %s", cache);
                    stderr.writefln("REGISTRY: %s", registry);
                    stderr.writefln("SANDBOX:  %s", sbDir);
                    stderr.writefln("COMMAND:  %s", cmd);
                    stderr.writefln("STATUS:   %s", status);
                    stderr.writeln("STDOUT ---------------");
                    foreach (l; File(outPath, "r").byLine(Yes.keepTerminator))
                    {
                        stderr.write(l);
                    }
                    stderr.writeln("----------------------");
                    stderr.writeln("STDERR ---------------");
                    foreach (l; File(errPath, "r").byLine(Yes.keepTerminator))
                    {
                        stderr.write(l);
                    }
                    stderr.writeln("----------------------");
                    if (reg)
                    {
                        stderr.writeln("REGISTRY STDOUT ------");
                        foreach (l; File(reg.outPath, "r").byLine(Yes.keepTerminator))
                        {
                            stderr.write(l);
                        }
                        stderr.writeln("----------------------");
                        stderr.writeln("REGISTRY STDERR ------");
                        foreach (l; File(reg.errPath, "r").byLine(Yes.keepTerminator))
                        {
                            stderr.write(l);
                        }
                        stderr.writeln("----------------------");
                    }
                    outputShown = true;
                }
                stderr.writeln("ASSERTION FAILED: ", failMsg);
                numFailed++;
            }
        }

        // in case of success, we delete the sandbox dir,
        // otherwise we leave it here as it might be useful
        // to look at its content for debug

        if (numFailed == 0)
            rmdirRecurse(sbDir);

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
        return absolutePath(expandEnvVars(name, env), cwd);
    }

    File file(string name)
    {
        return File(filepath(name), "r");
    }
}

class Registry
{
    Pid pid;
    string outPath;
    string errPath;
    File outFile;
    File errFile;
    string url;
    int port;

    this(string exe, int port, string[string] env, string testName)
    {
        import std.conv : to;

        outPath = e2ePath("sandbox", testName, "registry.stdout");
        errPath = e2ePath("sandbox", testName, "registry.stderr");

        outFile = File(outPath, "w");
        errFile = File(errPath, "w");

        this.port = port;

        const cmd = [
            exe, port.to!string
        ];
        pid = spawnProcess(cmd, stdin, outFile, errFile, env, Config.none, e2ePath("sandbox", testName, "registry"));
        url = env["DOP_REGISTRY"];
    }

    int stop()
    {
        import core.time : msecs;
        import vibe.http.client : HTTPClientSettings, HTTPMethod, requestHTTP;

        // check if still running (otherwise it probably crashed)
        auto res = pid.tryWait();
        if (res.terminated)
        {
            writeln("registry terminated with code ", res.status);
            return res.status;
        }

        const stopUrl = url ~ "/api/v1/stop";
        auto settings = new HTTPClientSettings;
        settings.defaultKeepAliveTimeout = 0.msecs;

        requestHTTP(
            stopUrl,
            (scope req) { req.method = HTTPMethod.POST; },
            (scope res) {},
            settings
        );

        int ret = pid.wait();

        outFile.close();
        errFile.close();

        return ret;
    }
}

string e2ePath(Args...)(Args args)
{
    return buildNormalizedPath(dirName(__FILE_FULL_PATH__), args);
}

void copyRecurse(string src, string dest)
in (exists(src) && isDir(src))
in (!exists(dest) || !isFile(dest))
{
    mkdirRecurse(dest);

    foreach (e; dirEntries(src, SpanMode.breadth))
    {
        const relative = relativePath(e.name, src);
        const path = buildPath(dest, relative);

        if (e.isDir)
            mkdir(path);
        else
            copy(e.name, path);
    }
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

    const regExe = absolutePath(environment["DOP_E2E_REG"]);

    try
    {
        auto test = Test.parseFile(args[1]);
        test.check();
        return test.perform(dopExe, regExe);
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
