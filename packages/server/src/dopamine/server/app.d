module dopamine.server.app;

import dopamine.server.auth;
import dopamine.server.config;
import dopamine.server.db;
import dopamine.server.utils;
import dopamine.server.v1;

import cors_vibe;

import vibe.core.core;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.tls;

import std.file;
import std.format;
import std.path;
import std.string;

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

    URLRouter root;
    URLRouter api;

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

        api = new URLRouter("/api");
        api.any("*", cors());

        auto auth = new AuthApi(client);
        auth.setupRoutes(api);

        auto v1 = v1Api(client);
        v1.setupRoutes(api);

        debug
        {
            if (conf.testStopRoute)
                api.post("/stop", &stop);
        }

        root = new URLRouter;
        root.any("/api/*", api);

        // setup front-end
        string publicFolder = thisExePath
            .dirName
            .dirName
            .buildPath("share", "dopamine", "public")
            .buildNormalizedPath();

        debug
        {
            if (!exists(publicFolder))
            {
                publicFolder = __FILE_FULL_PATH__
                    .dirName
                    .dirName
                    .dirName
                    .dirName
                    .dirName
                    .dirName
                    .buildPath("web", "dist")
                    .buildNormalizedPath();
            }
        }

        logInfo("Serving front-end from %s", publicFolder);

        root.get("/assets/*", serveStaticFiles(publicFolder));
        root.get("/favicon.ico", serveStaticFile(buildPath(publicFolder, "favicon.ico")));
        auto indexService = serveStaticFile(buildPath(publicFolder, "index.html"));
        root.get("*", (scope req, scope resp) {
            // missed api and asset requests yield 404
            if (req.path.startsWith("/api/") || req.path.startsWith("/assets/"))
                return;
            // all other routes serve index.html to let vue-router do its job
            indexService(req, resp);
        });
    }

    HTTPListener listen()
    {
        return listenHTTP(settings, root);
    }

    debug
    {
        void stop(HTTPServerRequest req, HTTPServerResponse resp)
        {
            resp.writeBody("", 200);
            client.finish();
            exitEventLoop();
        }
    }
}
