module pgd.conv;

import pgd.libpq.defs;

import std.array;
import std.bitmanip;
import std.meta;
import std.traits;

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

private template typeOid(TT)
{
    alias T = Unqual!TT;

    static if (is(T == bool))
        enum typeOid = BOOLOID;
    else static if (is(T == short) || is(T == ushort))
        enum typeOid = INT2OID;
    else static if (is(T == int) || is(T == uint))
        enum typeOid = INT4OID;
    else static if (is(T == long) || is(T == ulong))
        enum typeOid = INT8OID;
    else static if (is(T == float))
        enum typeOid = FLOAT4OID;
    else static if (is(T == double))
        enum typeOid = FLOAT8OID;
    else static if (isString!T)
        enum typeOid = TEXTOID;
    else static if (isByteArray!T)
        enum typeOid = BYTEAOID;
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

private size_t scalarBinSize(T)(T val) if (isScalar!T)
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
private size_t emplaceScalar(T)(T val, ubyte[] buf)
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
        buf[0 .. val.length] = cast(immutable(ubyte)[]) val[]; // add [] to support static arrays
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

    @property int num()
    {
        assert(values.length == oids.length);
        assert(values.length == lengths.length);
        assert(values.length == formats.length);
        return cast(int) values.length;
    }
}

/// ditto
package PgQueryParams pgQueryParams(Args...)(Args args)
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

        params.oids[i] = typeOid!T;
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
