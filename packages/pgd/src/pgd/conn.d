module pgd.conn;

import pgd.libpq;
import pgd.conv;
import pgd.result;

import std.array;
import std.conv;
import std.exception;
import std.meta;
import std.string;
import std.traits;
import std.typecons;
import std.stdio : File;
import core.exception;

// exporting a few Postgresql enums
alias ConnStatus = pgd.libpq.ConnStatus;
alias PostgresPollingStatus = pgd.libpq.PostgresPollingStatus;

class ConnectionException : Exception
{
    mixin basicExceptionCtors!();
}

class ExecutionException : Exception
{
    mixin basicExceptionCtors!();
}

class ResultLayoutException : Exception
{
    mixin basicExceptionCtors!();
}

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
///
/// By default the exec function family are synchronous
/// which mean that they will block the calling thread until the result is received
/// from the server.
/// To perform asynchronous calls, the PgConn class shall be subclassed
/// and the pollResult method provide implementation to poll on the socket.
class PgConn
{
    private PGconn* conn;
    private bool inTransac;
    private int transacSavePoint;
    // A provision of counters for results.
    private int[64] refCounts;

    private this(const(char)* conninfo, Flag!"async" async = No.async)
    {
        if (async)
        {
            conn = enforce!OutOfMemoryError(PQconnectStart(conninfo));

            if (PQstatus(conn) == ConnStatus.BAD)
                badConnection(conn);
        }
        else
        {
            conn = enforce!OutOfMemoryError(PQconnectdb(conninfo));

            if (PQstatus(conn) != ConnStatus.OK)
                badConnection(conn);
        }
    }

    this(string conninfo, Flag!"async" async = No.async)
    {
        this(conninfo.toStringz(), async);
    }

    @property final ConnStatus status() const
    {
        return PQstatus(conn);
    }

    @property final PostgresPollingStatus connectPoll()
    {
        return PQconnectPoll(conn);
    }

    void finish()
    {
        PQfinish(conn);
    }

    final void resetStart()
    {
        if (!PQresetStart(conn))
            badConnection(conn);
    }

    @property final PostgresPollingStatus resetPoll()
    {
        return PQresetPoll(conn);
    }

    final void reset()
    {
        PQreset(conn);
    }

    @property final string errorMessage() const
    {
        return PQerrorMessage(conn).fromStringz.idup;
    }

    /// The file descriptor of the socket that communicate with the server.
    /// Can be used for polling on the conneciton.
    @property final int socket()
    {
        const sock = PQsocket(conn);
        if (sock == -1)
            badConnection(conn);
        return sock;
    }

    @property final bool isBusy()
    {
        return !!PQisBusy(conn);
    }

    final void consumeInput()
    {
        if (!PQconsumeInput(conn))
            badConnection(conn);
    }

    final void trace(File dest)
    {
        PQtrace(conn, dest.getFP());
    }

    final void untrace()
    {
        PQuntrace(conn);
    }

    /// wait for result by polling on the socket
    /// default impl does nothing
    protected void pollResult()
    {
    }

    /// Execute a transaction and return whatever is returned by the transaction handler.
    /// `START TRANSACTION` is executed before the handler and either `COMMIT` or `ROLLBACK`
    /// is executed after depending on whether an exception is thrown in the handler.
    ///
    /// `handler` must be a function or delegate accepting a scope PgTransac object.
    ///
    /// Nested transactions are also supported by use of savePoint
    auto transac(H)(H handler)
    {
        static assert(is(typeof(handler())), "function must not take any parameter");
        alias Ret = typeof(handler());

        const savePoint = transacSavePoint;
        const rootTransac = savePoint == 0;

        if (rootTransac)
            exec("START TRANSACTION");
        else
            exec(format("SAVEPOINT pgd_savepoint_%s", savePoint));

        transacSavePoint += 1;
        scope (exit)
            transacSavePoint -= 1;

        try
        {
            static if (is(Ret == void))
                handler();
            else
                auto res = handler();

            if (rootTransac)
                exec("COMMIT");

            static if (!is(Ret == void))
                return res;
        }
        catch (ConnectionException connEx)
        {
            throw connEx;
        }
        catch (Exception ex)
        {
            if (rootTransac)
                exec("ROLLBACK");
            else
                exec("SAVEPOINT pgd_savepoint_%s", savePoint);
            throw ex;
        }
    }

    /// Execute a SQL statement expecting no result.
    void exec(Args...)(string sql, Args args)
    {
        sendPriv!false(sql, args);

        pollResult();

        auto res = getLastResult();
        scope (exit)
            PQclear(res);

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, sql, args);

        if (status != ExecStatus.COMMAND_OK)
            badResultLayout("Expected an empty result", res);
    }

    T execScalar(T, Args...)(string sql, Args args) if (isScalar!T)
    {
        sendPriv!true(sql, args);

        pollResult();

        auto res = getLastResult();
        scope (exit)
            PQclear(res);

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, sql, args);

        if (PQntuples(res) != 1 || PQnfields(res) != 1)
            badResultLayout("Expected a single row and single column", res);

        return convScalar!T(0, 0, res);
    }

    T[] execScalars(T, Args...)(string sql, Args args) if (isScalar!T)
    {
        sendPriv!true(sql, args);

        pollResult();

        auto res = getLastResult();
        scope (exit)
            PQclear(res);

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, sql, args);

        if (PQnfields(res) != 1)
            badResultLayout("Expected a single column", res);

        const nrows = PQntuples(res);
        if (!nrows)
            return [];

        T[] scalars = uninitializedArray!(T[])(nrows);
        foreach (ri; 0 .. nrows)
            scalars[ri] = convScalar!T(ri, 0, res);

        return scalars;
    }

    /// Execute a SQL statement expecting a single row result.
    /// Result row is converted to the provided struct type.
    R execRow(R, Args...)(string sql, Args args) if (isRow!R)
    {
        sendPriv!true(sql, args);

        pollResult();

        auto res = getLastResult();
        scope (exit)
            PQclear(res);

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, sql, args);

        if (PQntuples(res) != 1)
            badResultLayout("Expected a single row", res);

        auto colInds = getColIndices!R(res);
        auto row = convRow!R(colInds, 0, res);

        return row;
    }

    /// Execute a SQL statement expecting a zero or many row result.
    /// Result rows are converted to the provided struct type.
    R[] execRows(R, Args...)(string sql, Args args) if (isRow!R)
    {
        sendPriv!true(sql, args);

        pollResult();

        auto res = getLastResult();
        scope (exit)
            PQclear(res);

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, sql, args);

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

    private void sendPriv(bool withResults, Args...)(string sql, Args args)
    {
        // PQsendQueryParams is needed to specify that we need results in binary format
        // The downside is that it does not allow to send multiple sql commands at once
        // (; separated in the same string)
        // so when no result is expected and no param is needed we use PQsendQuery

        static if (Args.length > 0)
        {
            // TODO: debug check that maximum index in sql is not greater than args.length
            auto params = pgQueryParams(args);

            auto res = PQsendQueryParams(conn, sql.toStringz(),
                cast(int) params.num, &params.oids[0], &params.values[0], &params.lengths[0], &params.formats[0], 1
            );
        }
        else static if (withResults)
        {
            auto res = PQsendQueryParams(conn, sql.toStringz(),
                0, null, null, null, null, 1
            );
        }
        else
        {
            auto res = PQsendQuery(conn, sql.toStringz());
        }

        if (res != 1)
            badConnection(conn);
    }

    private PGresult* getLastResult()
    {
        PGresult* last;
        PGresult* res = enforce!OutOfMemoryError(PQgetResult(conn));
        while (res)
        {
            if (last)
                PQclear(last);
            last = res;
            res = PQgetResult(conn);
        }

        if (PQstatus(conn) == ConnStatus.BAD)
            badConnection(conn);

        return last;
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

    string escapeLiteral(T)(T val) if (isScalar!T)
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

private:

@property bool isError(ExecStatus status)
{
    switch (status)
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

noreturn badConnection(PGconn* conn)
{
    const msg = PQerrorMessage(conn).fromStringz.idup;
    throw new ConnectionException(msg);
}

noreturn badExecution(Args...)(PGresult* res, string sql, Args args)
{
    const msg = formatExecErrorMsg(res, sql, args);
    throw new ExecutionException(msg);
}

noreturn badResultLayout(string expectation, PGresult* res)
{
    const rowCount = PQntuples(res);
    const rowPlural = rowCount > 1 ? "s" : "";
    const colCount = PQnfields(res);
    const colPlural = colCount > 1 ? "s" : "";
    const msg = expectation ~ format(
        " - received a result with %s row%s and %s column%s",
        rowCount, rowPlural, colCount, colPlural
    );
    throw new ResultLayoutException(msg);
}

string formatExecErrorMsg(Args...)(PGresult* res, string sql, Args args)
{
    string msg = "Error during query execution.\n";
    msg ~= "SQL:\n" ~ sql ~ "\n";
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
