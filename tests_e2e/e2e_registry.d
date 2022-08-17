module e2e_registry;

import e2e_sandbox;
import e2e_test;
import e2e_utils;

import std.conv;
import std.format;
import std.process;
import std.stdio;

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

    this(Exes exes, Sandbox sandbox)
    {
        outPath = sandbox.path("registry.stdout");
        errPath = sandbox.path("registry.stderr");

        outFile = File(outPath, "w");
        errFile = File(errPath, "w");

        this.port = sandbox.port;
        assert(this.port != 0);
        this.url = format!"http://localhost:%s"(sandbox.port);
        this.env["DOP_REGISTRY_HOSTNAME"] = "localhost";
        this.env["DOP_REGISTRY_PORT"] = sandbox.port.to!string;
        this.env["DOP_DB_CONNSTRING"] = pgConnString(format("dop-test-%s", sandbox.port));
        this.env["DOP_TEST_STOPROUTE"] = "1";
        version (DopRegistryFsStorage)
            this.env["DOP_REGISTRY_STORAGEDIR"] = sandbox.path("storage");

        const regPath = sandbox.registryPath();

        const adminCmd = [
            exes.admin,
            "--create-db",
            "--test-create-users",
            "--test-populate-from", regPath,
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

        const cmd = [exes.registry];
        pid = spawnProcess(cmd, stdin, outFile, errFile, this.env, Config.none, regPath);

        // ensure that server is correctly booted
        import core.thread : Thread;
        import core.time : msecs;
        Thread.sleep(500.msecs);

        auto res = pid.tryWait();
        if (res.terminated)
            throw new Exception(format!"registry crashed at startup with code %s"(res.status));
    }

    int stop()
    {
        import vibe.http.client : HTTPClientSettings, HTTPMethod, requestHTTP;

        // check if still running (otherwise it probably crashed)
        auto res = pid.tryWait();
        if (res.terminated)
        {
            writeln("registry terminated with code ", res.status);
            return res.status;
        }

        version (Posix)
        {
            import core.sys.posix.signal : SIGINT;

            pid.kill(SIGINT);
        }
        version (Windows)
        {
            pid.kill(0);
        }

        int code = pid.wait();

        outFile.close();
        errFile.close();

        return code;
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

    void reportOutput(File report)
    {
        reportFileContent(report, outPath, "STDOUT of Registry");
        reportFileContent(report, errPath, "STDERR of Registry");
    }
}
