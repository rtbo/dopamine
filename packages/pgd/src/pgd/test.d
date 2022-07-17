module pgd.test;

version (unittest)  : import pgd.conn;
import pgd.connstring;

import std.process;

string adminConnString()
{
    return environment.get("PGD_TEST_ADMIN_DB", "postgres:///postgres");
}

string dbConnString()
{
    return environment.get("PGD_TEST_DB", "postgres:///test-pgd");
}

shared static this()
{
    const info = breakdownConnString(dbConnString());
    const dbName = info["dbname"];

    auto db = new PgConn(adminConnString());
    scope (exit)
        db.finish();

    const dbIdent = db.escapeIdentifier(dbName);

    db.exec("DROP DATABASE IF EXISTS " ~ dbIdent);
    db.exec("CREATE DATABASE " ~ dbIdent);
}
