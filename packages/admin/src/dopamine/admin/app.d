module dopamine.admin.app;

import dopamine.admin.config;
import pgd.conn;

import std.exception;
import std.getopt;
import std.stdio;
import std.string;

immutable(string[string]) migrations;

shared static this()
{
    migrations["v1"] = import("v1.sql");
}

version (DopAdminMain) int main(string[] args)
{
    bool createDb;
    string[] migrationsToRun;

    // dfmt off
    auto helpInfo = getopt(args,
        "create-db",        &createDb,
        "run-migration",    &migrationsToRun,
    );
    // dfmt on

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("Admin tool for dopamine registry", helpInfo.options);
        return 0;
    }

    if (!createDb && !migrationsToRun.length)
    {
        writeln("Nothing to do!");
        return 0;
    }

    int res;
    foreach (mig; migrationsToRun)
    {
        auto sql = mig in migrations;
        if (!sql)
        {
            stderr.writefln("%s: No such migration", mig);
            res += 1;
        }
    }
    if (res)
        return res;

    auto conf = Config.get;

    if (createDb)
    {
        auto db = new PgConn(conf.adminConnString);
        scope (exit)
            db.dispose();

        createDatabase(db, conf.dbConnString);
    }

    auto db = new PgConn(conf.dbConnString);
    scope (exit)
        db.dispose();

    foreach (mig; migrationsToRun)
    {
        writefln("Running migration \"%s\"", mig);
        db.execSync(migrations[mig]);
    }

    return 0;
}

void createDatabase(PgConn db, string connString)
{
    import std.format;

    const info = breakdownConnString(connString);
    writeln(info);

    const dbName = *enforce("dbname" in info, "Could not find DB name in " ~ connString);

    writefln(`(Re)creating database "%s"`, dbName);

    const dbIdent = db.escapeIdentifier(dbName);

    db.execSync("DROP DATABASE IF EXISTS " ~ dbIdent);
    db.execSync("CREATE DATABASE " ~ dbIdent);
}
