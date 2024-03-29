module dopamine.registry.config;

import std.conv;

@safe:

/// Server and configuration.
/// Fields are read from environment variables.
/// Defaults values should suit development environement.
struct Config
{
    /// Hostname of registry (without port)
    /// Read from $DOP_REGISTRY_HOSTNAME
    string registryHostname;

    /// Port of the registry
    /// Read from $DOP_REGISTRY_PORT or $PORT if $DOP_REGISTRY_PORT is unset
    ushort registryPort;

    /// Secret of JWT signature
    /// Read from $DOP_REGISTRY_JWTSECRET
    string registryJwtSecret;

    /// Path to the HTTPS certificate file
    /// Read from $DOP_HTTPS_CERT
    string httpsCert;

    /// Path to the HTTPS key file
    /// Read from $DOP_HTTPS_KEY
    string httpsKey;

    /// Origin of the front-end website
    /// Read from $DOP_FRONTEND_ORIGIN
    string frontendOrigin;

    /// Connection string of the database
    /// Read from $DOP_DB_CONNSTRING
    string dbConnString;

    /// Database connection pool size
    /// Read from $DOP_DB_POOLMAXSIZE
    uint dbPoolMaxSize;

    /// Github OAuth client Id
    /// Read from $DOP_GITHUB_CLIENTID
    string githubClientId;

    /// Github OAuth client secret
    /// Read from $DOP_GITHUB_CLIENTSECRET
    string githubClientSecret;

    /// Google OAuth client Id
    /// Read from $DOP_GOOGLE_CLIENTID
    string googleClientId;

    /// Google OAuth client secret
    /// Read from $DOP_GOOGLE_CLIENTSECRET
    string googleClientSecret;

    version (DopRegistryFsStorage)
    {
        /// Storage directory, if FileSystemStorage is used
        /// Read from $DOP_REGISTRY_STORAGEDIR
        string registryStorageDir;
    }

    /// Whether to setup a stop route
    /// Only used in testing
    /// Read from $DOP_TEST_STOPROUTE
    bool testStopRoute;

    static @property const(Config) get()
    {
        import std.path;
        import std.process : environment;

        static Config c;
        static bool initialized;

        if (!initialized)
        {
            c.registryHostname = environment.get(
                "DOP_REGISTRY_HOSTNAME", "localhost"
            );
            c.registryPort = environment.get(
                "DOP_REGISTRY_PORT", environment.get("PORT", "3500")
            ).to!ushort;

            c.registryJwtSecret = environment.get(
                "DOP_REGISTRY_JWTSECRET", "test-secret"
            );

            c.httpsCert = environment.get(
                "DOP_HTTPS_CERT", null,
            );
            c.httpsKey = environment.get(
                "DOP_HTTPS_KEY", null,
            );

            c.frontendOrigin = environment.get(
                "DOP_FRONTEND_ORIGIN", "localhost:3000"
            );

            c.dbConnString = environment.get(
                "DOP_DB_CONNSTRING", "postgres:///dop-registry"
            );
            c.dbPoolMaxSize = environment.get(
                "DOP_DB_POOLMAXSIZE", "5"
            ).to!uint;

            c.githubClientId = environment.get(
                "DOP_GITHUB_CLIENTID", "3f2f6c2ce1e0bdf8ae6c"
            );
            c.githubClientSecret = environment.get(
                "DOP_GITHUB_CLIENTSECRET", "Not a secret"
            );

            c.googleClientId = environment.get(
                "DOP_GOOGLE_CLIENTID", "241559404387-jf6rp461t5ikahsgrjop48jm5u97ur5t.apps.googleusercontent.com"
            );
            c.googleClientSecret = environment.get(
                "DOP_GOOGLE_CLIENTSECRET", "Not a secret"
            );

            version (DopRegistryFsStorage)
            {
                c.registryStorageDir = environment["DOP_REGISTRY_STORAGEDIR"];
            }

            c.testStopRoute = environment.get("DOP_TEST_STOPROUTE", null) !is null;

            initialized = true;
        }

        return c;
    }
}
