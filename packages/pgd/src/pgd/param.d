module pgd.param;

import pgd.conv;
import pgd.conv.nullable;
import pgd.maybe;
import pgd.libpq.defs;

import std.array;
import std.traits;
import std.typecons;

@safe:

/// A query parameter known at runtime
interface PgParam
{
    @property Oid oid() const;
    @property const(char)[] value() const;
    @property bool binary() const;
}

/// Build a `PgParam` from the provided value
PgParam pgParam(T)(T value) if (isScalar!(Unqual!T))
{
    static if (sizeKnownAtCt!T)
    {
        auto res = new CtSzParam!(scalarBinSizeCt!T);
    }
    else
    {
        auto res = new RtSzParam(scalarBinSize(value));
    }
    res._oid = cast(Oid) pgTypeOf!T;
    emplaceScalar(value, cast(ubyte[])(res._value[]));

    return res;
}

version (unittest)
{
    import pgd.test;
    import pgd.conn;
}

@("PgParam")
unittest
{
    import std.datetime;

    auto db = new PgConn(dbConnString());
    scope (exit)
        db.finish();

    PgParam[] params;
    params ~= pgParam("some text");
    params ~= pgParam(12);
    params ~= pgParam(true);
    params ~= pgParam(12.2);
    params ~= pgParam(Date(1989, 11, 9));

    @OrderedCols
    static struct R
    {
        string text;
        int i;
        bool b;
        double d;
        Date date;
    }

    db.sendDyn("SELECT $1, $2, $3, $4, $5", params);
    const r = db.getRow!R();

    assert(r.text == "some text");
    assert(r.i == 12);
    assert(r.b);
    assert(r.d == 12.2);
    assert(r.date == Date(1989, 11, 9));
}

private class CtSzParam(size_t N) : PgParam
{
    private Oid _oid;
    private char[N] _value;

    @property Oid oid() const
    {
        return _oid;
    }

    @property const(char)[] value() const
    {
        return _value[];
    }

    @property bool binary() const
    {
        return true;
    }
}

private class RtSzParam : PgParam
{
    private Oid _oid;
    private char[] _value;

    this(size_t sz)
    {
        _value = new char[sz];
    }

    @property Oid oid() const
    {
        return _oid;
    }

    @property const(char)[] value() const
    {
        return _value;
    }

    @property bool binary() const
    {
        return true;
    }
}

/// Bind query args to parameters to PQexecParams or similar
package(pgd) struct PgQueryParams
{
    Oid[] oids;
    const(char)*[] values;
    int[] lengths;
    int[] formats;

    static PgQueryParams uninitialized(size_t num) @system
    {
        auto oids = uninitializedArray!(Oid[])(num);
        auto values = uninitializedArray!(const(char)*[])(num);
        auto lf = uninitializedArray!(int[])(2 * num);
        auto lengths = lf[0 .. num];
        auto formats = lf[num .. $];

        return PgQueryParams(oids, values, lengths, formats);
    }

    @property int num() @safe
    {
        assert(values.length == oids.length);
        assert(values.length == lengths.length);
        assert(values.length == formats.length);
        return cast(int) values.length;
    }
}

/// ditto
package(pgd) PgQueryParams pgQueryParams(Args...)(Args args) @trusted
{
    auto res = PgQueryParams.uninitialized(Args.length);

    // all values are written to the same array
    size_t valuesSize;

    // dfmt off
    static foreach (i, arg; args)
    {{
        alias T = Unqual!(typeof(arg));
        static assert(isScalar!T, T(arg).stringof ~ " is not a supported scalar type");

        static if (sizeKnownAtCt!T)
            enum thisSz = scalarBinSizeCt!T;
        else
            const thisSz = scalarBinSize(arg);

        res.oids[i] = cast(Oid)pgTypeOf!T;
        res.lengths[i] = cast(int)thisSz;
        res.formats[i] = 1; // binary
        valuesSize += thisSz;
    }}

    auto valuesBuf = new ubyte[valuesSize];
    size_t offset;

    static foreach (i, arg; args)
    {{
        const sz = emplaceScalar(arg, valuesBuf[offset .. $]);
        if (sz > 0 || !isNullable!(Args[i]))
        {
            res.values[i] = cast(const(char)*)&valuesBuf[offset];
            offset += sz;
        }
        else
        {
            res.values[i] = null;
        }
    }}
    // dfmt on

    assert(offset == valuesBuf.length);

    return res;
}

@("pgQueryParams")
unittest
{
    int i = 21;
    string s = "blabla";
    MayBe!(string, null) ns;
    ubyte[] blob = [4, 5, 6, 7];
    int* pi;
    Nullable!int ni = 12;

    auto params = pgQueryParams(i, s, ns, blob, pi, ni);

    assert(cast(TypeOid[]) params.oids == [
            TypeOid.INT4, TypeOid.TEXT, TypeOid.TEXT, TypeOid.BYTEA, TypeOid.INT4,
            TypeOid.INT4
        ]);
    assert(params.lengths == [4, 6, 0, 4, 0, 4]);
    assert(params.values.length == 6);
    assert(params.values[0]!is null);
    assert(params.values[1]!is null);
    assert(params.values[2] is null);
    assert(params.values[3]!is null);
    assert(params.values[4] is null);
    assert(params.values[5]!is null);
}

/// ditto
package(pgd) PgQueryParams pgQueryDynParams(const(PgParam)[] params) @trusted
{
    auto res = PgQueryParams.uninitialized(params.length);

    foreach (i, param; params)
    {
        auto val = param.value;
        const bin = param.binary;
        res.oids[i] = param.oid;
        res.lengths[i] = cast(int) val.length;
        if (!bin)
            val ~= '\0';
        res.values[i] = &val[0];
        res.formats[i] = bin ? 1 : 0;
    }

    return res;
}
