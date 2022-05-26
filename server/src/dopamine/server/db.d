module dopamine.server.db;

import dopamine.c.libpq;
import dopamine.server.config;

import vibe.core.connectionpool;

import std.string;
import core.time;

class DbClient
{
    ConnectionPool!DbConn pool;

    /// Create a connection pool with specfied size, each connection specified by connString
    this(string conninfo, uint size)
    {
        const conninfoz = conninfo.toStringz();

        pool = new ConnectionPool!DbConn(() @safe => new DbConn(conninfoz), size);
    }

    LockedConnection!DbConn lockConnection()
    {
        return pool.lockConnection();
    }
}

class DbConn
{
    private PGconn* pg;

    private this(const(char)* conninfo) @trusted
    {
        pg = pgEnforceStatus(PQconnectdb(conninfo));
    }

    this(string conninfo) @safe
    {
        this(conninfo.toStringz());
    }

    void dispose()
    {
        PQreset(pg);
    }

    /// Execute a single statement expecting no result.
    /// Thread is blocked until response is received from the server
    void execSync(string sql)
    {
        auto res = PQexec(pg, sql.toStringz());

        pg.pgEnforce(PQresultStatus(res) == ExecStatus.COMMAND_OK);
    }
}

version (FormatDb)
{
    void formatDb()
    {
        const conf = Config.get;

        const dbName = extractDbName(conf.dbConnString);

        auto conn = new DbConn(conf.dbFormatConnString);
        scope (exit)
            conn.dispose();

        conn.execSync("DROP DATABASE IF EXISTS " ~ dbName);
        conn.execSync("CREATE DATABASE " ~ dbName);
    }
}

private:

PGconn* pgEnforceStatus(PGconn* pg)
{
    if (PQstatus(pg) != ConnStatus.OK)
    {
        const msg = PQerrorMessage(pg).fromStringz().idup;
        throw new Exception(msg);
    }
    return pg;
}

auto pgEnforce(C)(PGconn* pg, C cond)
{
    if (!cond)
    {
        const msg = PQerrorMessage(pg).fromStringz().idup;
        throw new Exception(msg);
    }
    return cond;
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
