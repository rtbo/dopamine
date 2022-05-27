module dopamine.admin.app;

import dopamine.c.libpq;
import dopamine.server.config;
import dopamine.server.db;

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
        auto db = new DbConn(conf.adminConnString);
        scope (exit)
            db.dispose();

        const dbName = extractDbName(conf.dbConnString);

        createDatabase(db, dbName);
    }

    auto db = new DbConn(conf.dbConnString);
    scope (exit)
        db.dispose();

    foreach (mig; migrationsToRun)
    {
        writefln("Running migration \"%s\"", mig);
        db.execSync(migrations[mig]);
    }

    return 0;
}

void createDatabase(DbConn db, string dbName)
{
    import std.format;

    writefln(`(Re)creating database "%s"`, dbName);

    const dbIdent = db.escapeIdentifier(dbName);

    db.execSync("DROP DATABASE IF EXISTS " ~ dbIdent);
    db.execSync("CREATE DATABASE " ~ dbIdent);
}

string extractDbName(string conninfo)
{
    const conninfoz = conninfo.toStringz();

    char* errmsg;
    PQconninfoOption* opts = PQconninfoParse(conninfoz, &errmsg);

    if (!opts)
    {
        const msg = errmsg.fromStringz().idup;
        throw new Exception("Could not parse connection string: " ~ msg);
    }

    auto orig = opts; // copy original pointer for freeing
    scope (exit)
        PQconninfoFree(orig);

    while (opts && opts.keyword)
    {
        if (opts.keyword.fromStringz() == "dbname")
            return opts.val.fromStringz().idup;

        opts++;
    }

    return null;
}

@("extractDbName")
unittest
{
    assert(extractDbName("postgres://") == null);
    assert(extractDbName("postgres:///adatabase") == "adatabase");
    assert(extractDbName("postgres://host:3210/adatabase") == "adatabase");
    assert(extractDbName("postgres://user@host:3210/adatabase") == "adatabase");
}
