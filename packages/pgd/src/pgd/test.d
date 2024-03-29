module pgd.test;

version (unittest)
{
    import pgd.conn;
    import pgd.connstring;

    import std.process;

    string adminConnString() @safe
    {
        return environment.get("PGD_TEST_ADMIN_DB", "postgres:///postgres");
    }

    string dbConnString() @safe
    {
        return environment.get("PGD_TEST_DB", "postgres:///test-pgd");
    }

    shared static this()
    {
        import std.format : format;

        const info = breakdownConnString(dbConnString());
        const dbName = info["dbname"];
        const user = info.get("user", null);

        auto db = new PgConn(adminConnString());
        scope (exit)
            db.finish();

        const dbIdent = db.escapeIdentifier(dbName);

        db.exec("DROP DATABASE IF EXISTS " ~ dbIdent);
        db.exec("CREATE DATABASE " ~ dbIdent);

        if (user && dbName)
            db.exec(format!`GRANT ALL PRIVILEGES ON DATABASE %s TO %s`(
                    db.escapeIdentifier(dbName),
                    db.escapeIdentifier(user)
            ));
    }
}
