module e2e_sandbox;

import e2e_utils;
import e2e_test;

import std.base64;
import std.exception;
import std.file;
import std.format;
import std.json;
import std.stdio;

final class Sandbox
{
    string name;
    int port;
    File lock;
    string[string] env;

    this(string name)
    {
        this.name = name;
    }

    string path(Args...)(Args args)
    {
        return e2ePath("sandbox", name, args);
    }

    string recipePath(Args...)(Args args)
    {
        return path("recipe", args);
    }

    string homePath(Args...)(Args args)
    {
        return path("home", args);
    }

    string cachePath(Args...)(Args args)
    {
        return homePath("cache", args);
    }

    string registryPath(Args...)(Args args)
    {
        return path("registry", args);
    }

    void clean()
    {
        const dir = path();
        if (exists(dir))
        {
            rmdirRecurse(dir);
        }
        if (lock.isOpen)
            lock.close();
    }

    void prepare(Test test, Exes exes)
    {
        import std.algorithm : each, map;

        const dir = path();
        enforce(!exists(dir), "Sandbox already exists at " ~ dir);

        mkdirRecurse(dir);

        copyRecurse(e2ePath("recipes", test.recipe), recipePath());

        auto defs = parseJSON(cast(string) read(e2ePath("definitions.json")));

        mkdirRecurse(homePath("cache"));
        if (test.cache)
        {
            defs["caches"][test.cache].array
                .map!(jv => jv.str)
                .each!((p) {
                    const src = e2ePath("registry", p);
                    const dest = cachePath(p);
                    copyRecurse(src, dest);
                });
        }

        if (test.registry)
        {
            defs["registries"][test.registry].array
                .map!(jv => jv.str)
                .each!((p) {
                    const src = e2ePath("registry", p);
                    const dest = registryPath(p);
                    copyRecurse(src, dest);
                });
            acquirePortLock();
            env["DOP_REGISTRY"] = format!"http://localhost:%s"(port);
        }

        if (test.user)
        {
            enforce(test.registry, "USER entry needs a REGISTRY entry");
            auto usr = defs["users"][test.user];
            const email = usr["email"].str;

            const token = Base64.encode(cast(const(ubyte)[]) email).idup;
            auto loginFile = File(homePath("login.json"), "w");
            loginFile.writefln!`{"localhost:%s":"%s"}`(port, token);
        }

        env["DOP"] = exes.dop;
        env["DOP_HOME"] = homePath();
        env["DOP_E2ETEST_BUILDID"] = path("build-id.hash");
    }

    private void acquirePortLock()
    {
        enum start = 3501;
        port = start;
        while (1)
        {
            const fn = e2ePath("sandbox", format("%d.lock", port));
            lock = File(fn, "w");
            if (lock.tryLock())
                return;

            enforce(port < start + 100, "Could not acquire sandbox port");
            port += 1;
        }
    }
}
