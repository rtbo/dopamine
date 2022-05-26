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
    /// Read from $DOP_DB_POOLMAXSIZE
    string dbPoolMaxSize;

    version (FormatDb)
    {
        /// Connection string to format (drop, then recreate) the database
        /// This connection must have DROP and CREATE DATABASE privileges.
        /// Read from $DOP_DB_FORMATCONNSTRING
        /// The dbname to be formatted is extracted from $DOP_DB_CONNSTRING
        string dbFormatConnString;
    }

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
                "DOP_DB_CONNSTRING", "postgres:///dop-registry"
            );
            c.dbPoolMaxSize = environment.get(
                "DOP_DB_POOLMAXSIZE", "1"
            );

            version (FormatDb)
            {
                c.dbFormatConnString = environment.get(
                    "DOP_DB_FORMATCONNSTRING", "postgres:///postgres"
                );
            }

            initialized = true;
        }

        return c;
    }
}
