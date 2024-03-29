module pgd.conn;

import pgd.libpq;
import pgd.conv;
import pgd.param;

import std.array;
import std.conv;
import std.exception;
import std.meta;
import std.string;
import std.traits;
import std.typecons;
import std.stdio : File;
import core.exception;

version(unittest)
{
    import pgd.test;
}

// exporting a few Postgresql enums
alias ConnStatus = pgd.libpq.ConnStatus;
alias PostgresPollingStatus = pgd.libpq.PostgresPollingStatus;

@safe:

/// Exception thrown when the connection could not be made or appear lost
class ConnectionException : Exception
{
    mixin basicExceptionCtors!();
}

/// Exception thrown when the execution of a query returns an error from the server
class ExecutionException : Exception
{
    mixin basicExceptionCtors!();
}

/// Exception thrown when the layout of the received results (number of rows and columns)
/// doesn't match with the expected call
class ResultLayoutException : Exception
{
    mixin basicExceptionCtors!();
}

/// Exception thrown when a query expecting a row returns none.
class ResourceNotFoundException : Exception
{
    mixin basicExceptionCtors!();
}

/// enum attached at UDA on a row struct
/// to indicate at compile time that the result columns
/// are in the same order than the row struct fields
enum OrderedCols;

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

alias TransacHandler(T) = T delegate() @safe;

/// An interface to a Postgresql connection.
/// This interface is single threaded and cannot be shared among threads.
/// It is safe however to use one PgConn instance per thread.
///
/// By default the exec function family are synchronous
/// which mean that they will block the calling thread until the result is received
/// from the server.
/// To perform asynchronous calls, the PgConn class shall be subclassed
/// and the pollResult method provide implementation to poll on the socket.
/// This is done in the dopamine.registry package (see dopamine.registry.db)
class PgConn
{
    private PGconn* conn;
    private bool inTransac;
    private int transacSavePoint;
    private string lastSql;
    // A provision of counters for results.
    private int[64] refCounts;

    private this(const(char)* conninfo, Flag!"async" async = No.async) @system
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

    this(string conninfo, Flag!"async" async = No.async) @trusted
    {
        this(conninfo.toStringz(), async);
    }

    @property final ConnStatus status() const scope @trusted nothrow
    {
        return PQstatus(conn);
    }

    @property final PostgresPollingStatus connectPoll() scope @trusted nothrow
    {
        return PQconnectPoll(conn);
    }

    void finish() scope @trusted nothrow
    {
        PQfinish(conn);
    }

    final void resetStart() scope @trusted
    {
        if (!PQresetStart(conn))
            badConnection(conn);
    }

    @property final PostgresPollingStatus resetPoll() scope @trusted nothrow
    {
        return PQresetPoll(conn);
    }

    final void reset() scope @trusted nothrow
    {
        PQreset(conn);
    }

    @property final string errorMessage() scope const @trusted
    {
        return PQerrorMessage(conn).fromStringz.idup;
    }

    /// The file descriptor of the socket that communicate with the server.
    /// Can be used for polling on the conneciton.
    @property final int socket() scope @trusted
    {
        const sock = PQsocket(conn);
        if (sock == -1)
            badConnection(conn);
        return sock;
    }

    @property final bool isBusy() scope @trusted nothrow
    {
        return !!PQisBusy(conn);
    }

    final void consumeInput() scope @trusted
    {
        if (!PQconsumeInput(conn))
            badConnection(conn);
    }

    final void trace(File dest) scope @trusted
    {
        PQtrace(conn, dest.getFP());
    }

    final void untrace() scope @trusted nothrow
    {
        PQuntrace(conn);
    }

    /// Wait for result by polling on the socket.
    /// Default impl does nothing, which has the effect that
    /// exec, execScalar etc. will block the current thread while waiting.
    void pollResult() scope @safe
    {
    }

    /// Execute a transaction and return whatever is returned by the transaction handler.
    /// `START TRANSACTION` is executed before the handler and either `COMMIT` or `ROLLBACK`
    /// is executed after depending on whether an exception is thrown in the handler.
    ///
    /// `handler` must be a function or delegate accepting a scope PgTransac object.
    ///
    /// Nested transactions are also supported by use of savePoint
    auto transac(H)(H handler) scope @trusted if (isSomeFunction!H && isSafe!H)
    {
        alias T = ReturnType!H;
        static assert(is(typeof(handler())), "handler must accept no parameter");
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
            static if (is(T == void))
                handler();
            else
                auto res = handler();

            if (rootTransac)
                exec("COMMIT");

            static if (!is(T == void))
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

    /// Send a SQL statement with params but do not wait for completion.
    /// Use the get method family to wait for completion.
    /// Multiple SQL statements are not allowed.
    void send(Args...)(string sql, Args args) scope @trusted
    {
        sendPriv!true(sql, args);
    }

    /// Send a SQL statement with dynamic params but do not wait for completion.
    /// Use the get method family to wait for completion.
    /// Multiple SQL statements are not allowed.
    void sendDyn(string sql, PgParam[] params) scope @trusted
    {
        lastSql = sql;

        int res;

        debug
        {
            validateSqlParams(sql, params.length);
        }

        if (params.length)
        {
            auto pgParams = pgQueryDynParams(params);

            res = PQsendQueryParams(conn, sql.toStringz(),
                cast(int) pgParams.num,
                &pgParams.oids[0],
                &pgParams.values[0],
                &pgParams.lengths[0],
                &pgParams.formats[0],
                1
            );
        }
        else
        {
            res = PQsendQueryParams(conn, sql.toStringz(),
                0, null, null, null, null, 1
            );
        }

        if (res != 1)
            badConnection(conn, sql);
    }

    void enableRowByRow() scope @trusted
    {
        int res = PQsetSingleRowMode(conn);
        if (!res)
            badConnection(conn);
    }

    /// Wait for completion of a previously sent query (with `send` or `sendDyn`)
    /// expecting no result
    void getNone() @trusted
    {
        auto res = getLastResult();
        scope (exit)
            PQclear(res);
        scope (exit)
            lastSql = null;

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, lastSql);

        if (status != ExecStatus.COMMAND_OK)
            badResultLayout("Expected an empty result", res);
    }

    /// Wait for completion of a previously sent query (with `send` or `sendDyn`)
    /// expecting a single scalar result
    T getScalar(T)() @trusted if (isScalar!T)
    {
        auto res = getLastResult();
        scope (exit)
            PQclear(res);
        scope (exit)
            lastSql = null;

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, lastSql);

        if (PQnfields(res) != 1)
            badResultLayout("Expected a single column", res);
        if (PQntuples(res) == 0)
            notFound();
        if (PQntuples(res) > 1)
            badResultLayout("Expected a single row and single column", res);

        return convScalar!T(0, 0, res);
    }

    /// Wait for completion of a previously sent query (with `send` or `sendDyn`)
    /// expecting multiple single scalar results (one scalar per row)
    T[] getScalars(T)() @trusted if (isScalar!T)
    {
        auto res = getLastResult();
        scope (exit)
            PQclear(res);
        scope (exit)
            lastSql = null;

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, lastSql);

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

    /// Wait for completion of a previously sent query (with `send` or `sendDyn`)
    /// expecting a single row result.
    /// Result row is converted to the provided struct type.
    R getRow(R)() @trusted if (isRow!R)
    {
        auto res = getLastResult();
        scope (exit)
            PQclear(res);
        scope (exit)
            lastSql = null;

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, lastSql);

        if (PQntuples(res) == 0)
            notFound();
        if (PQntuples(res) > 1)
            badResultLayout("Expected a single row", res);

        mixin(generateColIndexStruct!R());
        _ColIndices colInds = void;
        fillColIndices!R(res, colInds);

        auto row = convRow!R(colInds, 0, res);

        return row;
    }

    /// Wait for completion of a previously sent query (with `send` or `sendDyn`)
    /// expecting either a single or no row result.
    /// Result row is converted to the provided struct type.
    MayBe!R getMayBeRow(R)() @trusted if (isRow!R)
    {
        auto res = getLastResult();
        scope (exit)
            PQclear(res);
        scope (exit)
            lastSql = null;

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, lastSql);

        if (PQntuples(res) == 0)
            return MayBe!R(null);
        if (PQntuples(res) > 1)
            badResultLayout("Expected a single row", res);

        mixin(generateColIndexStruct!R());
        _ColIndices colInds = void;
        fillColIndices!R(res, colInds);

        auto row = convRow!R(colInds, 0, res);

        return MayBe!R(row);
    }

    /// Wait for completion of a previously sent query (with `send` or `sendDyn`)
    /// expecting zero or many rows result.
    /// Result rows are converted to the provided struct type.
    R[] getRows(R)() @trusted if (isRow!R)
    {
        auto res = getLastResult();
        scope (exit)
            PQclear(res);
        scope (exit)
            lastSql = null;

        const status = PQresultStatus(res);
        if (status.isError)
            badExecution(res, lastSql);

        const nrows = PQntuples(res);
        if (!nrows)
            return [];

        mixin(generateColIndexStruct!R());
        _ColIndices colInds = void;
        fillColIndices!R(res, colInds);

        R[] rows = uninitializedArray!(R[])(nrows);
        foreach (ri; 0 .. nrows)
        {
            rows[ri] = convRow!R(colInds, ri, res);
        }

        return rows;
    }

    /// Returns a D range of `R`, each element being a row
    /// fetched in the single row mode of PostgreSQL.
    /// A reference to the connection is in the returned object,
    /// which should not leave the scope of `this`.
    auto getRowByRow(R)() return scope @trusted if (isRow!R)
    {
        scope(exit)
            lastSql = null;

        PGresult* res1 = PQgetResult(conn);

        mixin(generateColIndexStruct!R());
        _ColIndices colInds;

        if (res1)
        {
            const status = PQresultStatus(res1);
            if (status.isError)
                badExecution(res1, lastSql);
            if (status != ExecStatus.SINGLE_TUPLE && status != ExecStatus.TUPLES_OK)
            {
                throw new Exception("RowByRow mode was not enabled");
            }
            if (status != ExecStatus.TUPLES_OK)
            {
                fillColIndices!R(res1, colInds);
            }
            else
            {
                while (res1)
                {
                    PQclear(res1);
                    res1 = PQgetResult(conn);
                }
            }
        }

        static struct RowRange
        {
            PGconn* conn;
            PGresult* res;
            _ColIndices colInds;
            string lastSql;

            @property R front() @trusted
            {
                return convRow!R(colInds, 0, res);
            }

            @property bool empty() @safe
            {
                return res is null;
            }

            void popFront() @trusted
            {
                if (res)
                    PQclear(res);

                res = PQgetResult(conn);
                if (!res)
                    return;

                const status = PQresultStatus(res);
                // if error, we drain then throw
                if (status.isError)
                {
                    const msg = formatExecErrorMsg(res, lastSql);
                    while (res)
                    {
                        PQclear(res);
                        res = PQgetResult(conn);
                    }
                    throw new ExecutionException(msg);
                }
                // if last, we drain the last results (should be the last one)
                if (status == ExecStatus.TUPLES_OK)
                {
                    while (res)
                    {
                        PQclear(res);
                        res = PQgetResult(conn);
                    }
                }
            }
        }

        return RowRange(conn, res1, colInds, lastSql);
    }

    @("getRowByRow")
    unittest
    {
        auto db = new PgConn(dbConnString());
        scope(exit)
            db.finish();

        db.exec(`
            CREATE TABLE row_by_row (
                id integer PRIMARY KEY,
                t1 text,
                t2 text,
                i1 integer,
                oddid boolean
            )
        `);
        scope (exit)
            db.exec("DROP TABLE row_by_row");

        for (int id=1; id<=1000; ++id)
        {
            db.exec(`
                INSERT INTO row_by_row (
                    id, t1, t2, i1, oddid
                ) VALUES (
                    $1, $2, $3, 3 * $1, mod($1, 2) <> 0
                )
            `, id, "Some text", "Another text for t2");
        }

        static struct R
        {
            int id;
            string t1;
            string t2;
            int i1;
            bool oddid;
        }

        auto rows = db.execRowByRow!R(`
            SELECT id, t1, t2, i1, oddid FROM row_by_row
        `);

        int id = 1;
        foreach (row; rows)
        {
            assert(row.id == id);
            assert(row.t1 == "Some text");
            assert(row.t2 == "Another text for t2");
            assert(row.i1 == id * 3);
            assert(row.oddid == ((id % 2) != 0));
            id++;
        }
        assert(id == 1001);
    }

    /// Execute a SQL statement expecting no result.
    /// It is possible to submit multiple statements separated with ';'
    void exec(Args...)(string sql, Args args) scope @trusted
    {
        sendPriv!false(sql, args);
        pollResult();
        getNone();
    }

    T execScalar(T, Args...)(string sql, Args args) scope @trusted if (isScalar!T)
    {
        sendPriv!true(sql, args);
        pollResult();
        return getScalar!T();
    }

    T[] execScalars(T, Args...)(string sql, Args args) scope @trusted if (isScalar!T)
    {
        sendPriv!true(sql, args);
        pollResult();
        return getScalars!T();
    }

    /// Execute a SQL statement expecting a single row result.
    /// Result row is converted to the provided struct type.
    R execRow(R, Args...)(string sql, Args args) scope @trusted if (isRow!R)
    {
        sendPriv!true(sql, args);
        pollResult();
        return getRow!R();
    }

    /// Execute a SQL statement expecting a single row result.
    /// Result row is converted to the provided struct type.
    MayBe!R execMayBeRow(R, Args...)(string sql, Args args) scope @trusted if (isRow!R)
    {
        sendPriv!true(sql, args);
        pollResult();
        return getMayBeRow!R();
    }

    /// Execute a SQL statement expecting a zero or many row result.
    /// Result rows are converted to the provided struct type.
    R[] execRows(R, Args...)(string sql, Args args) scope @trusted if (isRow!R)
    {
        sendPriv!true(sql, args);
        pollResult();
        return getRows!R();
    }

    auto execRowByRow(R, Args...)(string sql, Args args) @trusted if (isRow!R)
    {
        sendPriv!true(sql, args);
        enableRowByRow();
        pollResult();
        return getRowByRow!R();
    }

    private void sendPriv(bool withResults, Args...)(string sql, Args args) scope @trusted
    {
        // PQsendQueryParams is needed to specify that we need results in binary format
        // The downside is that it does not allow to send multiple sql commands at once
        // (; separated in the same string)
        // so when no result is expected and no param is needed we use PQsendQuery

        lastSql = sql;

        debug
        {
            validateSqlParams(sql, args.length);
        }

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

    private PGresult* getLastResult() @trusted
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

    string escapeIdentifier(string ident) @trusted
    {
        auto res = PQescapeIdentifier(conn, ident.ptr, ident.length);
        scope (exit)
            PQfreemem(cast(void*) res);

        return res.fromStringz.idup;
    }
}

void validateSqlParams(string sql, size_t paramCount)
{
    import std.regex;

    int maxNum;
    auto params = matchAll(sql, `\$(\d+)`);
    foreach (c; params)
    {
        const num = c[1].to!int;
        enforce(num <= paramCount, format!"Missing parameter for %s in sql query:\n%s"(
            c[0], sql
        ));
        if (num > maxNum)
            maxNum = num;
    }
    enforce(maxNum == paramCount, format!"Following SQL query received %s parameters but was expecting %s:\n%s"(
        paramCount, maxNum, sql
    ));
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

@system:

noreturn badConnection(PGconn* conn, string sendSql=null)
{
    string msg = PQerrorMessage(conn).fromStringz.idup;
    if (!msg.length)
    {
        msg = "PostgreSQL error while sending SQL:\n" ~ sendSql;
    }
    throw new ConnectionException(msg);
}

noreturn badExecution(Args...)(PGresult* res, string sql)
{
    const msg = formatExecErrorMsg(res, sql);
    throw new ExecutionException(msg);
}

noreturn badResultLayout(string expectation, PGresult* res)
{
    const rowCount = PQntuples(res);
    const rowPlural = rowCount > 1 ? "s" : "";
    const colCount = PQnfields(res);
    const colPlural = colCount > 1 ? "s" : "";
    const msg = format!"%s - received a result with %s row%s and %s column%s"(
        expectation, rowCount, rowPlural, colCount, colPlural
    );
    throw new ResultLayoutException(msg);
}

noreturn notFound()
{
    throw new ResourceNotFoundException("The expected resource could not be found");
}

string formatExecErrorMsg(PGresult* res, string sql) @system
{
    string msg = "Error during query execution.\n";
    msg ~= "SQL:\n" ~ sql ~ "\n";
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

void fillColIndices(R, CI)(const(PGresult)* res, ref CI inds)
{
    mixin(generateColNameStruct!R());

    enum expectedCount = (Fields!R).length;
    const colCount = PQnfields(res);

    enforce(colCount == expectedCount, format!"Expected %s columns, but result has %s"(
            expectedCount, colCount));

    static if (hasUDA!(R, OrderedCols))
    {
        static foreach (i, f; FieldNameTuple!R)
            __traits(getMember, inds, f) = cast(int) i;
    }
    else
    {
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

        // dfmt off
        static foreach (f; FieldNameTuple!R)
        {{
            if (__traits(getMember, inds, f) == -1)
            {
                const name = __traits(getMember, names, f);
                __traits(getMember, inds, f) = PQfnumber(res, name.toStringz);
            }

            const ind = __traits(getMember, inds, f);
            enforce(ind >= 0 && ind < colCount, "Cannot lookup column index for " ~ R.stringof ~ "." ~ f);
        }}
        // dfmt on
    }
}
