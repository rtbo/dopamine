module dopamine.server;

import vibe.core.core;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;

import std.exception;
import std.file;
import std.path;
import std.string;

/// Server configuration.
/// Fields are read from environment variables.
struct Config
{
    /// Hostname of registry (without port)
    /// Read from $DOP_SERVER_HOSTNAME
    string hostname;

    /// Port of the registry
    /// Read from $DOP_SERVER_PORT or $PORT if $DOP_SERVER_PORT is unset
    ushort port;

    static @property const(Config) get()
    {
        import std.conv : to;
        import std.process : environment;

        static Config c;
        static bool initialized;

        if (!initialized)
        {
            c.hostname = environment.get(
                "DOP_SERVER_HOSTNAME", "0.0.0.0"
            );
            c.port = environment.get(
                "DOP_SERVER_PORT", environment.get("PORT", "80")
            ).to!ushort;

            initialized = true;
        }

        return c;
    }
}

int main()
{
    setLogLevel(LogLevel.debugV);

    const conf = Config.get;
    auto settings = new HTTPServerSettings(conf.hostname);
    settings.port = conf.port;

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
                .buildPath("web", "dist")
                .buildNormalizedPath();
        }
    }

    enforce(exists(publicFolder) && isDir(publicFolder), `public folder "` ~ publicFolder ~ `" not found`);
    logInfo("Serving front-end from %s", publicFolder);

    auto router = new URLRouter;
    router.get("/assets/*", serveStaticFiles(publicFolder));
    router.get("/favicon.ico", serveStaticFile(buildPath(publicFolder, "favicon.ico")));
    auto indexService = serveStaticFile(buildPath(publicFolder, "index.html"));
    router.get("*", (scope req, scope resp) {
        // missed api and asset requests yield 404
        if (req.path.startsWith("/api/") || req.path.startsWith("/assets/"))
            return;
        // all other routes serve index.html to let vue-router do its job
        indexService(req, resp);
    });

    listenHTTP(settings, router);

    return runApplication();
}
