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
