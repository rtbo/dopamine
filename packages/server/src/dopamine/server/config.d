module dopamine.server.config;

/// Server and configuration.
/// Fields are read from environment variables.
/// Defaults values should suit development environement.
struct Config
{
    /// Hostname of server (including port)
    /// Read from $DOP_SERVER_HOSTNAME
    string serverHostname;

    /// Connection string of the database
    /// Read from $DOP_DB_CONNSTRING
    string dbConnString;

    /// Database connection pool size
    /// Read from $DOP_DB_POOLMAXSIZE
    string dbPoolMaxSize;

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

            c.dbConnString = environment.get(
                "DOP_DB_CONNSTRING", "postgres:///dop-registry"
            );
            c.dbPoolMaxSize = environment.get(
                "DOP_DB_POOLMAXSIZE", "1"
            );

            initialized = true;
        }

        return c;
    }
}
