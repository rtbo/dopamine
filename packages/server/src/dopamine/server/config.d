module dopamine.server.config;

import std.conv;

@safe:

/// Server and configuration.
/// Fields are read from environment variables.
/// Defaults values should suit development environement.
struct Config
{
    /// Hostname of server (including port)
    /// Read from $DOP_SERVER_HOSTNAME
    string serverHostname;

    /// Secret of JWT signature
    /// Read from $DOP_SERVER_JWTSECRET
    string serverJwtSecret;

    /// Connection string of the database
    /// Read from $DOP_DB_CONNSTRING
    string dbConnString;

    /// Database connection pool size
    /// Read from $DOP_DB_POOLMAXSIZE
    uint dbPoolMaxSize;

    /// Whether to setup a stop route
    /// Only used in testing
    /// Read from $DOP_TEST_STOPROUTE
    bool testStopRoute;

    static @property Config get()
    {
        import std.process : environment;

        static Config c;
        static bool initialized;

        if (!initialized)
        {
            c.serverHostname = environment.get(
                "DOP_SERVER_HOSTNAME", "localhost:3000"
            );
            c.serverJwtSecret = environment.get(
                "DOP_SERVER_JWTSECRET", "test-secret"
            );

            c.dbConnString = environment.get(
                "DOP_DB_CONNSTRING", "postgres:///dop-registry"
            );
            c.dbPoolMaxSize = environment.get(
                "DOP_DB_POOLMAXSIZE", "1"
            ).to!uint;

            c.testStopRoute = environment.get("DOP_TEST_STOPROUTE", null) !is null;

            initialized = true;
        }

        return c;
    }
}
