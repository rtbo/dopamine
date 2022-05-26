module dopamine.server.app;

import dopamine.server.config;
import dopamine.server.db;

import vibe.core.args;
import vibe.core.core;
import vibe.http.router;
import vibe.http.server;

import std.conv;
import std.format;

enum currentApiLevel = 1;

version (DopServerMain) void main(string[] args)
{
    version (FormatDb)
    {
        import std.algorithm : find, remove;

        const f = args.find("--format-db");
        if (f.length != 0)
        {
            formatDb();
            args = args.remove(args.length - f.length);
        }
    }

    setCommandLineArgs(args);

    const conf = Config.get;

    auto settings = new HTTPServerSettings(conf.serverHostname);

    const prefix = format("/api/v%s", currentApiLevel);
    auto router = new URLRouter(prefix);

    auto listener = listenHTTP(settings, router);
    scope (exit)
        listener.stopListening();

    runApplication();
}
