module pgd.conv;

import pgd.libpq;

import std.algorithm;
import std.array;
import std.bitmanip;
import std.conv;
import std.exception;
import std.format;
import std.meta;
import std.traits;

class UnsupportedTypeException : Exception
{
    Oid oid;

    this(Oid oid, string file = __FILE__, size_t line = __LINE__)
    {
        super("Encountered PostgreSQL type not supported by PGD: " ~ oid.to!string, file, line);
        this.oid = oid;
    }
}

enum PgType
{
    boolean = 16,
    smallint = 21,
    integer = 23,
    bigint = 20,
    real_ = 700,
    doublePrecision = 701,
    bytea = 17,
    text = 25,
}

package immutable(TypeOid[]) supportedTypes = [
    TypeOid.BOOL, TypeOid.BYTEA, TypeOid.INT8, TypeOid.INT2, TypeOid.INT4, TypeOid.TEXT, TypeOid.FLOAT4, TypeOid.FLOAT8
];

package PgType enforceSupported(TypeOid oid)
{
    if (!supportedTypes.canFind(oid))
        throw new UnsupportedTypeException(oid);
    return cast(PgType)oid;
}

package bool isSupportedType(TypeOid oid)
{
    return supportedTypes.canFind(oid);
}

enum isScalar(T) = isString!T || isNumeric!T || is(T == bool) || isByteArray!T;
enum isRow(R) = is(R == struct) && allSatisfy!(isScalar, Fields!R);

private alias ElType(T) = Unqual!(typeof(T.init[0]));
private enum isByte(T) = is(T == byte) || is(T == ubyte);
private enum isByteArray(T) = isArray!T && isByte!(ElType!T);
private enum isString(T) = isArray!T && is(ElType!T == char);
static assert(isByteArray!(const(ubyte)[]));
static assert(isByteArray!(const(byte)[]));
static assert(isByteArray!(ubyte[]));
static assert(isByteArray!(byte[]));

static assert(isScalar!bool);
static assert(isScalar!short);
static assert(isScalar!int);
static assert(isScalar!long);
static assert(isScalar!uint);
static assert(isScalar!(byte[]));
static assert(isScalar!(char[]));
static assert(isScalar!(ubyte[12]));
static assert(isScalar!string);
// FIXME: debug check at runtime that the encoding of the database is UTF-8
static assert(!isScalar!wstring); // no UTF-16 support, user must convert to string before

private struct SomeRow
{
    int i;
    float f;
    bool b;
    byte[] blob;
    string text;
}

private struct NotSomeRow
{
    int i;
    float f;
    bool b;
    byte[] blob;
    string text;
    SomeRow row;
}

static assert(isRow!SomeRow);
static assert(!isRow!NotSomeRow);
static assert(!isScalar!SomeRow);

package T convScalar(T)(int rowInd, int colInd, const(PGresult)* res) @system
{
    const len = PQgetlength(res, rowInd, colInd);
    const pval = PQgetvalue(res, rowInd, colInd);
    const val = pval[0 .. len];
    const text = PQfformat(res, colInd) == 0;

    if (text)
    {
        // FIXME: probably not suited to all conversions (e.g. bin encoding)
        return val.to!T;
    }
    else
    {
        const binVal = BinValue(cast(const(ubyte)[]) val, enforceSupported(PQftype(res, colInd)));
        return toScalar!T(binVal);
    }
}

package R convRow(R, CI)(CI colInds, int rowInd, const(PGresult)* res) @system
{
    R row = void;
    // dfmt off
    static foreach (f; FieldNameTuple!R)
    {{
        alias T = typeof(__traits(getMember, row, f));
        const colInd = __traits(getMember, colInds, f);
        __traits(getMember, row, f) = convScalar!T(rowInd, colInd, res);
    }}
    // dfmt on
    return row;
}

private struct BinValue
{
    const(ubyte)[] val;
    PgType type;

    void check(PgType enforceType, size_t enforceSize, string typename) @safe
    {
        enforce(
            type == enforceType,
            format("Expected PostgreSQL type %s to build a %s but received %s", enforceType, typename, type)
        );
        enforce(
            val.length == enforceSize,
            format("Expected a size of %s to build a %s but received %s", enforceSize, typename, val.length)
        );
    }
}

private bool toScalar(T)(BinValue val) @safe if (is(T == bool))
{
    val.check(PgType.boolean, 1, "bool");
    return val.val[0] != 0;
}

private T toScalar(T)(BinValue val) @safe if (isNumeric!T)
{
    val.check(pgTypeOf!T, T.sizeof, T.stringof);
    const ubyte[T.sizeof] be = val.val[0 .. T.sizeof];
    return bigEndianToNative!T(be);
}

// UTF-8 is not checked, hence @system
private T toScalar(T)(BinValue val) @system if (isString!T)
{
    enforce(val.type == PgType.text, "FIXME: msg oid string");
    return (cast(const(char)[]) val.val).idup;
}

private T toScalar(T)(BinValue val) @safe if (isByteArray!T && isStaticArray!T)
{
    val.check(PgType.bytea, T.length, "FIXME: msg oid ubyte[]");
    T arr = (cast(const(ElType!T)[]) val.val)[0 .. T.length];
    return arr;
}

private T toScalar(T)(BinValue val) @safe if (isByteArray!T && isDynamicArray!T)
{
    enforce(val.type == PgType.bytea, "FIXME: msg oid ubyte[]");
    return cast(ElType!T[]) val.val.dup;
}

private template pgTypeOf(TT)
{
    alias T = Unqual!TT;

    static if (is(T == bool))
        enum pgTypeOf = PgType.boolean;
    else static if (is(T == short) || is(T == ushort))
        enum pgTypeOf = PgType.smallint;
    else static if (is(T == int) || is(T == uint))
        enum pgTypeOf = PgType.integer;
    else static if (is(T == long) || is(T == ulong))
        enum pgTypeOf = PgType.bigint;
    else static if (is(T == float))
        enum pgTypeOf = PgType.real_;
    else static if (is(T == double))
        enum pgTypeOf = PgType.doublePrecision;
    else static if (isString!T)
        enum pgTypeOf = PgType.text;
    else static if (isByteArray!T)
        enum pgTypeOf = PgType.bytea;
    else
        static assert(false, "unsupported scalar type: " ~ T.stringof);
}

private template sizeKnownAtCt(TT) if (isScalar!TT)
{
    alias T = Unqual!TT;

    enum sizeKnownAtCt = is(T == bool) || isNumeric!T || isStaticArray!T;
}

private template scalarBinSizeCt(TT) if (isScalar!TT)
{
    alias T = Unqual!TT;

    static if (is(T == bool))
        enum scalarBinSizeCt = 1;
    else static if (isNumeric!T)
        enum scalarBinSizeCt = T.sizeof;
    else static if (isStaticArray!T && isByte!(ElType!T))
        enum scalarBinSizeCt = T.length;
    else
        static assert(false, "unknown compile-time size");
}

private size_t scalarBinSize(T)(T val) @safe if (isScalar!T)
{
    static if (is(T == bool))
        return 1;
    else static if (isNumeric!T)
        return T.sizeof;
    else static if (isString!T)
        return val.length;
    else static if (isByteArray!T)
        return val.length;
    else
        static assert(false, "unimplemented scalar type " ~ T.stringof);
}

/// write binary representation in array and return offset advance
private size_t emplaceScalar(T)(T val, ubyte[] buf) @safe
{
    assert(buf.length >= scalarBinSize(val));

    static if (is(T == bool))
    {
        buf[0] = val ? 1 : 0;
        return 1;
    }
    else static if (isNumeric!T)
    {
        buf[0 .. T.sizeof] = nativeToBigEndian(val);
        return T.sizeof;
    }
    else static if (isString!T || isByteArray!T)
    {
        buf[0 .. val.length] = cast(const(ubyte)[]) val[]; // add [] to support static arrays
        return val.length;
    }
}

/// Bind query args to parameters to PQexecParams or similar
package struct PgQueryParams
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
package PgQueryParams pgQueryParams(Args...)(Args args) @trusted
{
    auto params = PgQueryParams.uninitialized(Args.length);

    // all values are written to the same array
    size_t valuesSize;

    // dfmt off
    static foreach (i, arg; args)
    {{
        alias T = typeof(arg);
        static assert(isScalar!T, T(arg).stringof ~ " is not a supported scalar type");

        static if (sizeKnownAtCt!T)
            enum thisSz = scalarBinSizeCt!T;
        else
            const thisSz = scalarBinSize(arg);

        params.oids[i] = cast(Oid)pgTypeOf!T;
        params.lengths[i] = cast(int)thisSz;
        params.formats[i] = 1; // binary
        valuesSize += thisSz;
    }}

    auto valuesBuf = new ubyte[valuesSize];
    size_t offset;

    static foreach (i, arg; args)
    {{
        params.values[i] = cast(const(char)*)&valuesBuf[offset];
        offset += emplaceScalar(arg, valuesBuf[offset .. $]);
    }}
    // dfmt on

    assert(offset == valuesBuf.length);

    return params;
}
