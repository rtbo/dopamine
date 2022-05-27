module pgd.conn;

import pgd.libpq;

import std.conv;
import std.string;
import std.traits;

enum isDbScalar(T) = isSomeString!T || isIntegral!T || isFloatingPoint!T;

/// An interface to a Postgresql connection.
/// This interface is single threaded and cannot be shared among threads.
/// It is safe however to use one PgConn instance per thread.
class PgConn
{
    private PGconn* conn;

    // A provision of counters for results.
    private int[] refCounts;

    private this(const(char)* conninfo) @trusted
    {
        conn = pgEnforceStatus(PQconnectdb(conninfo));
    }

    this(string conninfo) @safe
    {
        this(conninfo.toStringz());
    }

    final void finish()
    {
        PQfinish(conn);
    }

    final void reset()
    {
        PQreset(conn);
    }

    /// The file descriptor of the socket that communicate with the server.
    /// Can be used for polling on the conneciton.
    final int socket()
    {
        return PQsocket(conn);
    }

    /// Send execution of a SQL statement
    /// Can be used in synchronous mode (if getting the result right after)
    /// or in asynchronous (e.g. by waiting on the socket to get the result)
    void send(Args...)(string sql, Args args)
    {
        sendPriv(sql, args);
        conn.pgEnforce(PQsetSingleRowMode(conn) == 1);
    }

    /// Execute a SQL statement expecting no result.
    /// Thread is blocked until response is received from the server
    void execSync(Args...)(string sql, Args args)
    {
        sendPriv(sql, args);

        auto res = PQgetResult(conn);
        conn.pgEnforce(res && (PQresultStatus(res) == ExecStatus.COMMAND_OK));

        // drain results (should be a single null at this point)
        while (res)
        {
            PQclear(res);
            res = PQgetResult(conn);
        }
    }

    private void sendPriv(Args...)(string sql, Args args)
    {
        static if (Args.length > 0)
        {
            // TODO: debug check that maximum index in sql is not greater than args.length
            auto params = pgQueryParams(args);

            auto res = PQsendQueryParams(conn, sql.toStringz(),
                cast(int) params.length, null, &params.values[0], &params.lengths[0], null, 0
            );
        }
        else
        {
            auto res = PQsendQuery(conn, sql.toStringz());
        }

        conn.pgEnforce(res == 1);
    }

    private PGresult* execPriv(Args...)(string sql, Args args)
    {
        static if (Args.length > 0)
        {
            // TODO: debug check that maximum index in sql is not greater than args.length
            auto params = pgQueryParams(args);

            return PQexecParams(conn, sql.toStringz(),
                cast(int) params.length, null, &params.values[0], &params.lengths[0], null, 0
            );
        }
        else
        {
            return PQexec(conn, sql.toStringz());
        }
    }

    string escapeLiteral(T)(T val) if (isDbScalar!T)
    {
        string sval = val.to!string;

        auto res = PQescapeLiteral(conn, sval.ptr, sval.length);
        scope (exit)
            PQfreemem(cast(void*) res);

        return res.fromStringz.idup;
    }

    string escapeIdentifier(string ident)
    {
        auto res = PQescapeIdentifier(conn, ident.ptr, ident.length);
        scope (exit)
            PQfreemem(cast(void*) res);

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

    for (auto opt = opts; opt && opt.keyword; opt++)
        if (opt.val)
            res[opt.keyword.fromStringz().idup] = opt.val.fromStringz().idup;

    return res;
}

version (unittest) import unit_threaded.assertions;

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

PGconn* pgEnforceStatus(PGconn* conn)
{
    if (PQstatus(conn) != ConnStatus.OK)
    {
        const msg = PQerrorMessage(conn).fromStringz().idup;
        throw new Exception(msg);
    }
    return conn;
}

auto pgEnforce(C)(PGconn* conn, C cond)
{
    if (!cond)
    {
        const msg = PQerrorMessage(conn).fromStringz().idup;
        throw new Exception(msg);
    }
    return cond;
}

struct PgQueryParams
{
    const(char)*[] values;
    int[] lengths;

    @property size_t length()
    {
        assert(values.length == lengths.length);
        return values.length;
    }

    @property void length(size_t newLen)
    {
        values.length = newLen;
        lengths.length = newLen;
    }
}

PgQueryParams pgQueryParams(Args...)(Args args)
{
    PgQueryParams params;
    params.length = Args.length;

    static foreach (i, arg; args)
    {
        string val = arg.to!string;
        params.values[i] = val.ptr;
        params.lengths[i] = cast(int) val.length;
    }
    return params;
}
