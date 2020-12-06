module dopamine.server.app;

import dopamine.server.middleware;

import vibe.core.log;
import vibe.db.mongo.mongo;
import vibe.vibe;

import std.file;
import std.path;

class AppConfig
{
    string dbUri;
    string dbName;

    string httpAddrV6;
    string httpAddrV4;
    ushort httpPort;

    static const(AppConfig) fromEnvironment()
    {
        import dopamine.server.loadenv : loadEnv;
        import std.conv : to;
        import std.process : environment;

        const envFile = thisExePath.dirName.buildPath(".env");
        loadEnv(envFile);

        auto config = new AppConfig;

        config.dbUri = environment.get("DB_URI", "mongodb://127.0.0.1");
        config.dbName = environment.get("DB_NAME", "dopamine");

        config.httpAddrV4 = environment.get("HTTP_ADDR_V4", "localhost");
        config.httpAddrV6 = environment.get("HTTP_ADDR_V6");
        config.httpPort = environment.get("HTTP_PORT", "8080").to!ushort;

        return config;
    }

    @property string[] bindAddresses() const
    {
        return httpAddrV6 ? [httpAddrV6, httpAddrV4] : [httpAddrV4];
    }

}

MongoClient connectMongo(const(AppConfig) config)
{
    MongoClientSettings settings;

    parseMongoDBUrl(settings, config.dbUri);
    settings.database = config.dbName;
    // settings.authMechanism = MongoAuthMechanism.scramSHA1;

    logInfo("connecting to MongoDb with URI '%s' and database '%s'", config.dbUri, config.dbName);

    return connectMongoDB(settings);
}

void main()
{
    const config = AppConfig.fromEnvironment();

    auto dbClient = connectMongo(config);

    auto settings = new HTTPServerSettings;
    settings.port = config.httpPort;
    settings.bindAddresses = config.bindAddresses;

    auto apiRouter = new URLRouter("/api");
    apiRouter.any("/*", &cors);
    apiRouter.get("/*", &hello);

    listenHTTP(settings, apiRouter);

    runApplication();
}

void cors(HTTPServerRequest req, HTTPServerResponse res)
{
    logInfo("%s cors %s", req.method, req.path);

    const method = "Access-Control-Request-Method" in req.headers;
    if (method)
    {
        logInfo("adding method %s", *method);
    }

    res.headers["Access-Control-Allow-Methods"] = "GET,POST,PUT";
    res.headers["Access-Control-Allow-Origin"] = "*";
}

void hello(HTTPServerRequest req, HTTPServerResponse res)
{
    logInfo("GET %s", req.path);

    logInfo("  params = %s", req.params);
    logInfo("  JSON = %s", req.json.toPrettyString());
    logInfo("  form = %s", req.form.toString());
    res.writeBody("Hello, World!");
}
