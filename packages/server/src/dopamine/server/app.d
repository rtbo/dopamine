module dopamine.server.app;

import dopamine.server.auth;
import dopamine.server.config;
import dopamine.server.db;
import dopamine.server.utils;
import dopamine.server.v1;

import cors_vibe;

import vibe.core.core;
import vibe.core.log;
import vibe.http.router;
import vibe.http.server;

import std.format;

version (DopServerMain) void main(string[] args)
{
    setLogLevel(LogLevel.trace);

    auto registry = new DopRegistry();
    auto listener = registry.listen();
    scope (exit)
        listener.stopListening();

    runApplication();
}

class DopRegistry
{
    DbClient client;
    HTTPServerSettings settings;
    URLRouter router;

    this()
    {
        const conf = Config.get;

        client = new DbClient(conf.dbConnString, conf.dbPoolMaxSize);

        settings = new HTTPServerSettings(conf.serverHostname);

        auto auth = new AuthApi(client);
        auto v1 = v1Api(client);

        const prefix = format("/api");
        router = new URLRouter(prefix);
        router.any("*", cors());

        auth.setupRoutes(router);
        v1.setupRoutes(router);

        if (conf.testStopRoute)
            router.post("/stop", &stop);

        router.get("*", &fallback);
    }

    HTTPListener listen()
    {
        return listenHTTP(settings, router);
    }

    void stop(HTTPServerRequest req, HTTPServerResponse resp)
    {
        resp.writeBody("", 200);
        client.finish();
        exitEventLoop();
    }

    void fallback(HTTPServerRequest req, HTTPServerResponse resp)
    {
        logInfo("fallback for %s", req.requestURI);
    }
}
