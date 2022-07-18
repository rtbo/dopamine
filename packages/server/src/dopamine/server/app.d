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
import vibe.stream.tls;

import std.format;

version (DopServerMain) void main(string[] args)
{
    setLogLevel(LogLevel.debugV);

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

        if (conf.httpsCert && conf.httpsKey)
        {
            settings.tlsContext = createTLSContext(TLSContextKind.server);
            settings.tlsContext.useCertificateChainFile(conf.httpsCert);
            settings.tlsContext.usePrivateKeyFile(conf.httpsKey);
        }

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
        return listenHTTP(settings, &rootHandler);
    }

    void rootHandler(scope HTTPServerRequest req, scope HTTPServerResponse resp)
    {
        if (req.path == "/" && req.method == HTTPMethod.GET) {
            const conf = Config.get;
            resp.redirect("http://" ~ conf.frontendOrigin);
            return;
        }

        router.handleRequest(req, resp);
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
