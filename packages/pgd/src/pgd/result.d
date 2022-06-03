module pgd.result;

import pgd.libpq;
import pgd.conv;

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

    @property Header header() return
    {
        assert(res);
        return Header(res);
    }

    /// number of rows
    @property size_t length() const
    {
        if (!res)
            return 0;
        return PQntuples(res);
    }

    Row opIndex(size_t ind) return
    {
        return Row(res, cast(int)ind);
    }
}

struct Header
{
    private PGresult *res;

    /// number of columns
    @property size_t length() const
    {
        return PQnfields(res);
    }

    Column opIndex(size_t ind) return
    {
        assert(ind < length);
        return Column(res, cast(int)ind);
    }

    Column opIndex(string name) return
    {
        auto number = PQfnumber(res, name.toStringz);
        enforce(number >= 0, "could not find column " ~ name);
        return Column(res, number);
    }
}

struct Column
{
    private PGresult *res;
    private int ind;

    string name() const
    {
        return PQfname(res, ind).fromStringz.idup;
    }

    int number() const
    {
        return ind;
    }

    int tableNumber() const
    {
        return PQftablecol(res, ind);
    }

    PgType type() const
    {
        return enforceSupported(PQftype(res, ind));
    }
}

struct Row
{
    private PGresult *res;
    private int ind;

    /// number of columns
    @property size_t length() const
    {
        return PQnfields(res);
    }

    Cell opIndex(size_t col) return
    {
        return Cell(res, ind, cast(int)col);
    }
}

struct Cell
{
    private PGresult *res;
    private int row;
    private int col;

    @property bool isNull() const
    {
        return !!PQgetisnull(res, row, col);
    }

    @property string value() const
    in(!isNull)
    {
        const len = PQgetlength(res, row, col);
        const ptr = PQgetvalue(res, row, col);
        return ptr[0 .. len].idup;
    }

    @property T to(T)() const
    {
        const len = PQgetlength(res, row, col);
        const ptr = cast(ubyte*)PQgetvalue(res, row, col);
        const type = enforceSupported(PQftype(res, ind));
        const val = BinValue(ptr[0 .. len], type);
        return toScalar!T(val);
    }
}
