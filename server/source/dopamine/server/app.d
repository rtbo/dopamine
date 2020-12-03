module dopamine.server.app;

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

    listenHTTP(settings, &hello);

    runApplication();
}

void hello(HTTPServerRequest req, HTTPServerResponse res)
{
    res.writeBody("Hello, World!");
}
