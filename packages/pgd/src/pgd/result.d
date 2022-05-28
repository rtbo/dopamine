module pgd.result;

import pgd.libpq;

import std.exception;
import std.string;

struct Result
{
    private PGresult *res;
    private int *rc;

    package
    this(PGresult* res, int *rc = null)
    {
        if (rc is null)
            rc = new int;

        assert(*rc == 0);
        *rc = 1;

        this.res = res;
        this.rc = rc;
    }

    this(this)
    {
        if (rc)
            *rc += 1;
    }

    ~this()
    {
        if (rc)
        {
            *rc -= 1;
            assert(*rc >= 0);
            if (!*rc)
            {
                PQclear(res);
            }
        }
    }

    bool opCast(T : bool)() const
    {
        return !!res;
    }

    @property Header header()
    {
        assert(res);
        return Header(this);
    }

    /// number of rows
    @property size_t length() const
    {
        if (!res)
            return 0;
        return PQntuples(res);
    }
}

struct Header
{
    private Result result;

    /// number of columns
    @property size_t length() const
    {
        return PQnfields(result.res);
    }

    Column opIndex(size_t ind)
    {
        assert(ind < length);
        return Column(result, cast(int)ind);
    }

    Column opIndex(string name)
    {
        auto number = PQfnumber(result.res, name.toStringz);
        enforce(number >= 0, "could not find column " ~ name);
        return Column(result, number);
    }
}

struct Column
{
    private Result result;
    private int ind;

    string name() const
    {
        return PQfname(result.res, ind).fromStringz.idup;
    }

    int number() const
    {
        return ind;
    }

    int tableNumber() const
    {
        return PQftablecol(result.res, ind);
    }
}

struct Row
{
    private Result result;
    private int ind;

    /// number of columns
    @property size_t length() const
    {
        return PQnfields(result.res);
    }

    Cell opIndex(size_t col)
    {
        return Cell(result, ind, cast(int)col);
    }
}

struct Cell
{
    private Result result;
    private int row;
    private int col;

    @property bool isNull() const
    {
        return !!PQgetisnull(result.res, row, col);
    }

    @property string value() const
    in(!isNull)
    {
        const len = PQgetlength(result.res, row, col);
        const ptr = PQgetvalue(result.res, row, col);
        return ptr[0 .. len].idup;
    }
}
