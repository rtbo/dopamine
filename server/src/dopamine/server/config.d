module dopamine.server.config;

struct Config
{
    /// Hostname of server (including port)
    /// Read from $DOP_SERVER_HOSTNAME
    string serverHostname;

    /// Connection string of the database
    /// Read from $DOP_DB_CONNSTRING
    string dbConnString;

    /// Database connection pool size
    /// Read from $DOP_DB_POOLSIZE
    string dbPoolSize;

    static @property Config get()
    {
        import std.process : environment;

        static Config c;
        static bool initialized;

        if (!initialized)
        {
            c.serverHostname = environment.get(
                "DOP_SERVER_HOSTNAME", "localhost:3500"
            );
            c.dbConnString = environment.get(
                "DOP_DB_CONNSTRING", "postgres://dop-registry"
            );
            c.dbPoolSize = environment.get(
                "DOP_DB_POOLSIZE", "1"
            );

            initialized = true;
        }

        return c;
    }
}


