module dopamine.config;

/// Admin tool configuration.
/// Fields are read from environment variables.
/// Defaults values should suit development environement.
struct Config
{
    /// Connection string of the database
    /// Read from $DOP_DB_CONNSTRING
    string dbConnString;

    /// Database connection pool size
    /// Read from $DOP_DB_POOLMAXSIZE
    string dbPoolMaxSize;

    /// Connection string to administrate the database.
    /// Requires privileges for:
    ///  - DROP DATABASE
    ///  - CREATE DATABASE
    ///  - DROP TABLE
    ///  - CREATE TABLE
    /// This connection must have DROP and CREATE DATABASE privileges.
    /// The name of the database to be administrated is extracted from $DOP_DB_CONNSTRING
    string adminConnString;

    static @property Config get()
    {
        import std.process : environment;

        static Config c;
        static bool initialized;

        if (!initialized)
        {
            c.dbConnString = environment.get(
                "DOP_DB_CONNSTRING", "postgres:///dop-registry"
            );
            c.dbPoolMaxSize = environment.get(
                "DOP_DB_POOLMAXSIZE", "1"
            );

            c.adminConnString = environment.get(
                "DOP_ADMIN_CONNSTRING", "postgres:///postgres"
            );

            initialized = true;
        }

        return c;
    }
}
