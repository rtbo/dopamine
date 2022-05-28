module pgd.conn;

import pgd.libpq;
import pgd.result;

import std.array;
import std.conv;
import std.exception;
import std.meta;
import std.string;
import std.traits;

enum isScalar(T) = isSomeString!T || isIntegral!T || isFloatingPoint!T;
enum isRow(R) = is(R == struct);

/// struct attached as UDA to provide at compile time
/// the column index in a query result.
/// If not supplied, the column index is fetched at run time from the member name.
struct ColInd
{
    int ind;
}

/// struct attached as UDA to provide at compile time
/// an alternative name for the lookup of column index in the query result
struct ColName
{
    string name;
}

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
        refCounts = new int[64];
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

    /// Execute a SQL statement expecting no result.
    /// Thread is blocked until response is received from the server
    void execSync(Args...)(string sql, Args args)
    {
        sendPriv(sql, args);

        auto res = PQgetResult(conn);

        scope (exit)
            clearAndDrain(res);

        conn.pgEnforce(res && (PQresultStatus(res) == ExecStatus.COMMAND_OK));
    }

    T execScalarSync(T, Args...)(string sql, Args args) if (isScalar!T)
    {
        sendPriv(sql, args);

        auto res = PQgetResult(conn);

        scope (exit)
            clearAndDrain(res);

        const status = PQresultStatus(res);
        if (status.isError)
        {
            throw new Exception(formatQueryMsg(res, sql, args));
        }

        enforce(PQnfields(res) == 1, "Expected a single column result");
        enforce(PQntuples(res) == 1, "Expected a single row result");

        return convScalar!T(0, 0, res);
    }

    T[] execScalarsSync(T, Args...)(string sql, Args args) if (isScalar!T)
    {
        sendPriv(sql, args);

        auto res = PQgetResult(conn);

        scope (exit)
            clearAndDrain(res);

        const status = PQresultStatus(res);
        if (status != ExecStatus.TUPLES_OK)
        {
            // FIXME: find out if error or if void and define exception types
            throw new Exception("FIXME");
        }
        // FIXME: throw if multiple columns

        const nrows = PQntuples(res);
        if (!nrows)
            return [];

        T[] scalars = uninitializedArray!(T[])(nrows);
        foreach (ri; 0 .. nrows)
        {
            scalars[ri] = convScalar!T(ri, 0, res);
        }

        return scalars;
    }

    /// Execute a SQL statement expecting a single row result.
    /// Result row is converted to the provided struct type.
    R execRowSync(R, Args...)(string sql, Args args) if (isRow!R)
    {
        sendPriv(sql, args);

        auto res = PQgetResult(conn);

        scope (exit)
            clearAndDrain(res);

        const status = PQresultStatus(res);
        if (status != ExecStatus.TUPLES_OK)
        {
            // FIXME: find out if error or if void and define exception types
            throw new Exception("FIXME");
        }

        // throw if multiple rows

        auto colInds = getColIndices!R(res);
        auto row = convRow!R(colInds, 0, res);

        return row;
    }

    /// Execute a SQL statement expecting a zero or many row result.
    /// Result rows are converted to the provided struct type.
    R[] execRowsSync(R, Args...)(string sql, Args args) if (isRow!R)
    {
        sendPriv(sql, args);

        auto res = PQgetResult(conn);

        scope (exit)
            clearAndDrain(res);

        const status = PQresultStatus(res);
        if (status != ExecStatus.TUPLES_OK)
        {
            // FIXME: find out if error or if void and define exception types
            throw new Exception("FIXME");
        }

        const nrows = PQntuples(res);
        if (!nrows)
            return [];

        auto colInds = getColIndices!R(res);

        R[] rows = uninitializedArray!(R[])(nrows);
        foreach (ri; 0 .. nrows)
        {
            rows[ri] = convRow!R(colInds, ri, res);
        }

        return rows;
    }

    private void clearAndDrain(PGresult* res)
    {
        while (res)
        {
            PQclear(res);
            res = PQgetResult(conn);
        }
    }

    /// Get the (untyped) result for the current query
    /// if result casts to false, it means there is no more result
    Result getResult()
    {
        auto res = PQgetResult(conn);
        // FIXME: check for error
        return Result(res, findRefCount());
    }

    private int* findRefCount()
    {
        for (size_t i = 0; i < refCounts.length; ++i)
        {
            if (refCounts[i] == 0)
                return &refCounts[i];
        }
        return null;
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

@property bool isError(ExecStatus status)
{
    switch(status)
    {
    case ExecStatus.EMPTY_QUERY:
    case ExecStatus.BAD_RESPONSE:
    case ExecStatus.NONFATAL_ERROR:
    case ExecStatus.FATAL_ERROR:
        return true;
    default:
        return false;
    }
}

string formatQueryMsg(Args...)(PGresult* res, string sql, Args args)
{
    string msg = "Error during query execution.\n";
    msg ~= "SQL:\n  " ~ sql ~ "\n";
    if (args.length)
    {
        msg ~= "Params:\n";
        static foreach (i, arg; args)
            msg ~= format("  $%s = %s\n", i + 1, arg);
    }
    const pgMsg = PQresultErrorMessage(res).fromStringz;
    msg ~= "PostgreSQL message: " ~ pgMsg;
    return msg ~ "\n";
}

/// Bind query args to parameters to PQexecParams or similar
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

/// ditto
PgQueryParams pgQueryParams(Args...)(Args args)
{
    PgQueryParams params;
    params.length = Args.length;

    static foreach (i, arg; args)
    {
        {
            string val = arg.to!string;
            params.values[i] = val.toStringz();
            params.lengths[i] = cast(int) val.length;
        }
    }
    return params;
}

/// Generate a struct that has integer fields
/// of the same name of the provided row type.
/// Used to cache indices of the columns
string generateColIndexStruct(R)() if (isRow!R)
{
    string res = "static struct _ColIndices {\n";

    static foreach (f; FieldNameTuple!R)
    {
        res ~= "    int " ~ f ~ ";\n";
    }

    res ~= "}";
    return res;
}

/// Generate a struct that has string fields
/// of the same name of the provided row type.
/// Used to cache customized names of the columns
string generateColNameStruct(R)() if (isRow!R)
{
    string res = "static struct _ColNames {\n";

    static foreach (f; FieldNameTuple!R)
    {
        res ~= "    string " ~ f ~ ";\n";
    }

    res ~= "}";
    return res;
}

auto getColIndices(R)(const(PGresult)* res)
{
    mixin(generateColIndexStruct!R());
    mixin(generateColNameStruct!R());

    _ColIndices inds = void;
    _ColNames names = void;

    static foreach (f; FieldNameTuple!R)
    {
        __traits(getMember, inds, f) = -1;
        __traits(getMember, names, f) = f;
    }

    alias colIndUDAs = getSymbolsByUDA!(R, ColInd);
    static foreach (indUDA; colIndUDAs)
    {
        __traits(getMember, inds, indUDA.stringof) = getUDAs!(indUDA, ColInd)[0].ind;
    }

    alias colNameUDAs = getSymbolsByUDA!(R, ColName);
    static foreach (nameUDA; colNameUDAs)
    {
        __traits(getMember, names, nameUDA.stringof) = getUDAs!(nameUDA, ColName)[0].name;
    }

    int ncols = PQnfields(res);

    // dfmt off
    static foreach (f; FieldNameTuple!R)
    {{
        if (__traits(getMember, inds, f) == -1)
        {
            const name = __traits(getMember, names, f);
            __traits(getMember, inds, f) = PQfnumber(res, name.toStringz);
        }

        const ind = __traits(getMember, inds, f);
        enforce(ind >= 0 && ind < ncols, "Cannot lookup column index for " ~ R.stringof ~ "." ~ f);
    }}
    // dfmt on

    return inds;
}

T convScalar(T)(int rowInd, int colInd, const(PGresult)* res)
{
    const len = PQgetlength(res, rowInd, colInd);
    const pval = PQgetvalue(res, rowInd, colInd);
    const val = pval[0 .. len];
    return val.to!T;
}

R convRow(R, CI)(CI colInds, int rowInd, const(PGresult)* res)
{
    R row = void;
    static foreach (f; FieldNameTuple!R)
    {
        {
            const colInd = __traits(getMember, colInds, f);
            const len = PQgetlength(res, rowInd, colInd);
            const pval = PQgetvalue(res, rowInd, colInd);
            const val = pval[0 .. len];
            __traits(getMember, row, f) = val.to!(typeof(__traits(getMember, row, f)));
        }
    }
    return row;
}

/// TODO: make dummy connection and dummy result for testing
