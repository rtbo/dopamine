module dopamine.registry.app;

import dopamine.registry.archive;
import dopamine.registry.auth;
import dopamine.registry.config;
import dopamine.registry.db;
import dopamine.registry.storage;
import dopamine.registry.utils;
import dopamine.registry.v1;

import cors_vibe;

import vibe.core.core;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.tls;

import std.exception;
import std.file;
import std.format;
import std.path;
import std.string;

version (DopRegistryMain) void main(string[] args)
{
    setLogLevel(LogLevel.debugV);

    auto registry = new DopRegistry();
    auto listener = registry.listen();
    scope (exit)
        listener.stopListening();

    runApplication();
}

final class DopRegistry
{
    DbClient client;
    HTTPServerSettings settings;

    URLRouter root;

    this()
    {
        const conf = Config.get;

        client = new DbClient(conf.dbConnString, conf.dbPoolMaxSize);

        settings = new HTTPServerSettings(conf.registryHostname);
        settings.port = conf.registryPort;

        if (conf.httpsCert && conf.httpsKey)
        {
            settings.tlsContext = createTLSContext(TLSContextKind.server);
            settings.tlsContext.useCertificateChainFile(conf.httpsCert);
            settings.tlsContext.usePrivateKeyFile(conf.httpsKey);
        }

        version (DopRegistryFsStorage) auto storage = new FileSystemStorage(conf.registryStorageDir);
        version (DopRegistryDbStorage) auto storage = new DatabaseStorage(client);

        static assert(is(typeof(storage) : Storage), "a suitable storage version must be defined");

        auto archiveMgr = new ArchiveManager(client, storage);

        version (DopRegistryServesFrontend)
            enum apiPrefix = "/api";
        else
            enum apiPrefix = "";

        auto api = new URLRouter(apiPrefix);
        api.any("*", cors());

        archiveMgr.setupRoutes(api);

        auto auth = new AuthApi(client);
        auth.setupRoutes(api);

        auto v1 = v1Api(client, archiveMgr);
        v1.setupRoutes(api);

        // Two possibilities for the deployment:
        //  1. API and front-end served by this app. Then a prefix is needed for the API
        //  2. API is served from a sub-domain (https://api.dopamine-pm.org).
        //     No prefix needed and the server is served by the "dop-server" app
        // The choice is determined by the DOP_REGISTRY_APIPREFIX environment variable

        version (DopRegistryServesFrontend)
        {
            setupFrontendService(api);
        }
        else
        {
            root = api;
        }

    }

    version (DopRegistryServesFrontend)
    {
        void setupFrontendService(URLRouter api)
        {
            root = new URLRouter;
            root.any("/api/*", api);

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
    }

    HTTPListener listen()
    {
        return listenHTTP(settings, root);
    }
}
