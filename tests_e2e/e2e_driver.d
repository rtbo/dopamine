/// Driver for end to end tests
///
/// Read one *.test file, run the provided command and perform the associated assertions
module e2e_driver;

import vibe.data.json;

import std.array;
import std.base64;
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

    override string expect(ref RunResult res)
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

    this(string path, Type type)
    {
        dirname = dirName(path);
        basename = baseName(path);
        this.type = type;
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
        string[] tries;
        foreach (name; names)
        {
            const path = buildPath(dirname, name);
            if (exists(path))
                return null;
            else
                tries ~= path;
        }
        auto msg = format("Could not find any library named %s in %s\nTried:", basename, dirname);
        foreach (tr; tries)
        {
            msg ~= "\n - " ~ tr;
        }
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

/// environment variable path separator
version (Posix)
    enum envPathSep = ':';
else version (Windows)
    enum envPathSep = ';';
else
    static assert(false);

/// Search for filename in the envPath variable content which can
/// contain multiple paths separated with sep depending on platform.
/// Returns: null if the file can't be found.
string searchInEnvPath(in string envPath, in string filename, in char sep = envPathSep)
{
    import std.algorithm : splitter;
    import std.file : exists;
    import std.path : buildPath;

    foreach (dir; splitter(envPath, sep))
    {
        const filePath = buildPath(dir, filename);
        if (exists(filePath))
            return filePath;
    }
    return null;
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

struct Test
{
    string name;
    string[] preCmds;
    string command;

    string recipe;
    string cache;
    string registry;
    string user;

    Expect[] expectations;

    Skip[] skips;

    static Test parseFile(string filename)
    {
        import std.algorithm : remove;

        const lineRe = regex(`^(EXPECT|ASSERT|SKIP)_([A-Z_]+)(\[(.*?)\])?(=(.+))?$`);

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

            enum preCmdMark = "PRE_CMD=";
            enum cmdMark = "CMD=";
            enum recipeMark = "RECIPE=";
            enum cacheMark = "CACHE=";
            enum registryMark = "REGISTRY=";
            enum userMark = "USER=";

            const mark = line.startsWith(
                preCmdMark, cmdMark, recipeMark, cacheMark, registryMark, userMark,
            );
            switch (mark)
            {
            case 1:
                test.preCmds ~= line[preCmdMark.length .. $];
                break;
            case 2:
                test.command = line[cmdMark.length .. $];
                break;
            case 3:
                test.recipe = line[recipeMark.length .. $];
                break;
            case 4:
                test.cache = line[cacheMark.length .. $];
                break;
            case 5:
                test.registry = line[registryMark.length .. $];
                break;
            case 6:
                test.user = line[userMark.length .. $];
                break;
            case 0:
            default:
                auto m = matchFirst(line, lineRe);
                enforce(!m.empty, format("%s: Unrecognized entry: %s", test.name, line));

                const mode = m[1];
                const type = m[2];
                const arg = m[4];
                const data = m[6];

                if (mode == "SKIP")
                {
                    switch (type)
                    {
                    case "NOPROG":
                        test.skips ~= new SkipNoProg(data);
                        break;
                    case "NOINET":
                        test.skips ~= new SkipNoInet;
                        break;
                    case "WINDOWS":
                    case "LINUX":
                    case "POSIX":
                        test.skips ~= new SkipOS(type);
                        break;
                    default:
                        throw new Exception("Unknown skip reason: " ~ type);
                    }
                    break;
                }

                Expect expect;

                switch (type)
                {
                case "FAIL":
                    statusExpect.expectFail = true;
                    expect = statusExpect;
                    test.expectations = remove!(exp => exp is statusExpect)(test.expectations);
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

                if (mode == "EXPECT")
                    test.expectations ~= expect;
                else if (mode == "ASSERT")
                    test.expectations ~= new Assert(expect);
                else
                    assert(false, "unknown assertion mode: " ~ mode);

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
        env["DOP_E2ETEST_BUILDID"] = sandboxPath("build-id.hash");
        return env;
    }

    // with all end-to-end tests run in //, it is necessary
    // to obtain a unique port for each instance
    Tuple!(File, int) acquireRegistryPort()
    {
        int port = 3501;
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

    void prepareUserLogin(string registry)
    {
        auto defs = parseJSON(cast(string) read(e2ePath("definitions.json")));

        auto usr = defs["users"][user];
        const email = usr["email"].str;

        const token = Base64.encode(cast(const(ubyte)[])email).idup;
        auto login = Json([
            registry: Json(token),
        ]);
        std.file.write(sandboxHomePath("login.json"), login.toString().representation);
    }

    int perform(string dopExe, string regExe, string adminExe)
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

            if (user)
                prepareUserLogin(format!"localhost:%s"(port));

            env["E2E_REGISTRY_PORT"] = port.to!string;
            env["DOP_REGISTRY"] = format!"http://localhost:%s"(port);
            reg = new Registry(regExe, adminExe, port, env, name);
        }

        foreach (preCmd; preCmds)
        {
            const cmd = expandEnvVars(preCmd, env);
            auto res = executeShell(cmd, env, Config.none, size_t.max, sandboxRecipePath);
            if (res.status != 0)
            {
                stderr.writeln("Pre-command failed:");
                stderr.writefln!"%s returned %s."(cmd, res.status);
                if (res.output)
                {
                    stderr.writeln("PRE-CMD STDOUT -------");
                    stderr.write(res.output);
                    stderr.writeln("----------------------");
                }
                if (reg)
                    reg.printOutput(stderr);
            }
        }

        const cmd = expandEnvVars(command, env);

        const outPath = sandboxPath("stdout");
        const errPath = sandboxPath("stderr");

        auto pid = spawnShell(
            cmd, stdin, File(outPath, "w"), File(errPath, "w"),
            env, Config.none, sandboxRecipePath
        );

        int status = pid.wait();

        if (reg)
        {
            enforce(reg.stop() == 0, "registry did not close normally");
        }

        if (exists(sandboxPath("build-id.hash")))
        {
            const hash = cast(string) assumeUnique(read(sandboxPath("build-id.hash")));
            env["DOP_BID_HASH"] = hash;
            env["DOP_BID"] = hash[0 .. 10];
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
                        stderr.write(l);
                    stderr.writeln("----------------------");
                    stderr.writeln("STDERR ---------------");
                    foreach (l; File(errPath, "r").byLine(Yes.keepTerminator))
                        stderr.write(l);
                    stderr.writeln("----------------------");
                    if (reg)
                        reg.printOutput(stderr);
                    outputShown = true;
                }
                stderr.writeln("ASSERTION FAILED: ", failMsg);
                numFailed++;

                if (cast(Assert) exp)
                    break;
            }
        }

        // in case of success, we delete the sandbox dir,
        // otherwise we leave it here as it might be useful
        // to look at its content for debug

        if (numFailed == 0 && !environment.get("E2E_KEEPSANDBOX"))
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

final class Registry
{
    Pid pid;
    string outPath;
    string errPath;
    File outFile;
    File errFile;
    string url;
    int port;
    string[string] env;

    this(string exe, string adminExe, int port, string[string] env, string testName)
    {
        import std.conv : to;

        outPath = e2ePath("sandbox", testName, "registry.stdout");
        errPath = e2ePath("sandbox", testName, "registry.stderr");

        outFile = File(outPath, "w");
        errFile = File(errPath, "w");

        this.port = port;
        this.url = format!"http://localhost:%s"(port);
        this.env["DOP_SERVER_HOSTNAME"] = "localhost";
        this.env["DOP_SERVER_PORT"] = port.to!string;
        this.env["DOP_DB_CONNSTRING"] = pgConnString(format("dop-test-%s", port));
        this.env["DOP_TEST_STOPROUTE"] = "1";

        const regPath = e2ePath("sandbox", testName, "registry");

        const adminCmd = [
            adminExe,
            "--create-db",
            "--run-migration", "v1",
            "--create-test-users",
            "--populate-from", regPath,
        ];
        auto adminEnv = this.env.dup;
        adminEnv["DOP_ADMIN_CONNSTRING"] = pgConnString("postgres");
        auto adminRes = execute(adminCmd, adminEnv);
        if (adminRes.status != 0)
            throw new Exception(
                format("dop-admin failed with code %s:\n%s", adminRes.status, adminRes.output)
            );
        else
            writeln("Run dop-admin:\n", adminRes.output);

        const cmd = [
            exe
        ];
        pid = spawnProcess(cmd, stdin, outFile, errFile, this.env, Config.none, regPath);
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

        const stopUrl = url ~ "/api/stop";
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

    string pgConnString(string dbName)
    {
        const pgUser = environment.get("PGUSER", null);
        const pgPswd = environment.get("PGPSWD", null);
        string query;
        if (pgUser)
        {
            query ~= format!"?user=%s"(pgUser);
            if (pgPswd)
                query ~= format!"&password=%s"(pgPswd);
        }
        return format!"postgres:///%s%s"(dbName, query);
    }

    void printOutput(File printFile)
    {
        printFile.writeln("REGISTRY STDOUT ------");
        foreach (l; File(outPath, "r").byLine(Yes.keepTerminator))
            printFile.write(l);
        printFile.writeln("----------------------");
        printFile.writeln("REGISTRY STDERR ------");
        foreach (l; File(errPath, "r").byLine(Yes.keepTerminator))
            printFile.write(l);
        printFile.writeln("----------------------");
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
        enforce(val, format!"Could not find %s in sandbox environment"(var));
        result ~= *val;
        var = null;
        env = false;
        mustach = false;
    }

    foreach (dchar c; input)
    {
        if (env && !mustach)
        {
            if (isAlphaNum(c) || c == '_')
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
        expand();

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

    const dopExe = absolutePath(environment["DOP"]);
    const regExe = absolutePath(environment["DOP_SERVER"]);
    const adminExe = absolutePath(environment["DOP_ADMIN"]);

    try
    {
        auto test = Test.parseFile(args[1]);
        test.check();

        string skipMsg = test.checkSkipMsg();
        if (skipMsg)
        {
            stderr.writeln("SKIP: ", skipMsg);
            return 77; // GNU skip return code
        }

        return test.perform(dopExe, regExe, adminExe);
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
