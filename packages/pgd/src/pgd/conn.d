module pgd.conn;

import pgd.libpq;

import std.conv;
import std.string;
import std.traits;

enum isDbLiteral(T) = isSomeString!T || isIntegral!T || isFloatingPoint!T;

class PgConn
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

    string escapeLiteral(T)(T val) if (isDbLiteral!T)
    {
        string sval = val.to!string;

        auto res = PQescapeLiteral(pg, sval.ptr, sval.length);
        scope(exit)
            PQfreemem(cast(void*)res);

        return res.fromStringz.idup;
    }

    string escapeIdentifier(string ident)
    {
        auto res = PQescapeIdentifier(pg, ident.ptr, ident.length);
        scope(exit)
            PQfreemem(cast(void*)res);

        return res.fromStringz.idup;
    }
}

string[string] breakdownConnString(string conninfo)
{
    const conninfoz = conninfo.toStringz();

    char* errmsg;
    PQconninfoOption* opts = PQconninfoParse(conninfoz, &errmsg);

    if (!opts)
    {
        const msg = errmsg.fromStringz().idup;
        throw new Exception("Could not parse connection string: " ~ msg);
    }

    scope (exit)
        PQconninfoFree(opts);

    string[string] res;

    for (auto opt=opts; opt && opt.keyword; opt++)
        if (opt.val)
            res[opt.keyword.fromStringz().idup] = opt.val.fromStringz().idup;

    return res;
}

version(unittest)
    import unit_threaded.assertions;

@("breakdownConnString")
unittest
{
    const bd0 = breakdownConnString("postgres://");
    const string[string] exp0;

    const bd1 = breakdownConnString("postgres:///adatabase");
    const string[string] exp1 = ["dbname": "adatabase"];

    const bd2 = breakdownConnString("postgres://somehost:3210/adatabase");
    const string[string] exp2 = [
        "host": "somehost",
        "port": "3210",
        "dbname": "adatabase",
    ];

    const bd3 = breakdownConnString("postgres://someuser@somehost:3210/adatabase");
    const string[string] exp3 = [
        "user": "someuser",
        "host": "somehost",
        "port": "3210",
        "dbname": "adatabase",
    ];

    bd0.shouldEqual(exp0);
    bd1.shouldEqual(exp1);
    bd2.shouldEqual(exp2);
    bd3.shouldEqual(exp3);
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
