module pgd.conv.nullable;

import std.traits;
import std.typecons;

template isNullable(T)
{
    enum isNullable = __traits(isSame, TemplateOf!T, Nullable) ||
        (!isStaticArray!T && is(typeof({ T val = null; })));
}

template NullableTarget(T)
{
    static if (__traits(isSame, TemplateOf!T, Nullable))
    {
        alias NullableTarget = typeof(T.init.get());
    }
    else static if (isPointer!T)
    {
        alias NullableTarget = PointerTarget!T;
    }
    else static if (isNullable!T)
    {
        alias NullableTarget = T;
    }
    else
    {
        alias NullableTarget = void;
    }
}

static assert(isNullable!(int*));
static assert(isNullable!(Nullable!int));
static assert(isNullable!(string));
static assert(isNullable!(ubyte[]));
static assert(!isNullable!(ubyte[32]));
static assert(is(NullableTarget!(int*) == int));
static assert(is(NullableTarget!(Nullable!int) == int));
static assert(is(NullableTarget!(string) == string));
static assert(is(NullableTarget!(ubyte[]) == ubyte[]));

bool isNull(T)(T maybe) if (isNullable!T)
{
    static if (__traits(isSame, TemplateOf!T, Nullable))
    {
        return maybe.isNull;
    }
    else
    {
        return maybe is null;
    }
}

@("isNull")
unittest
{
    import std.algorithm;
    int* pi;
    Nullable!int ni;
    //Nullable!(int, int.max) ni2;

    assert(isNull(pi));
    assert(isNull(ni));
    //assert(isNull(ni2));

    int i = 12;
    pi = &i;
    ni = i;
    //ni2 = i;
    assert(!isNull(pi));
    assert(!isNull(ni));
    //assert(!isNull(ni2));
}

auto getNonNull(T)(T val) if (isNullable!T)
in (!isNull(val))
{
    static if (__traits(isSame, TemplateOf!T, Nullable))
    {
        return val.get;
    }
    else static if (isPointer!T)
    {
        if (val is null)
            throw new Exception("non-null pointer!");
        return *val;
    }
    else
    {
        return val;
    }
}

T nullValue(T)() if (isNullable!T)
{
    static if (__traits(isSame, TemplateOf!T, Nullable))
    {
        return T.init;
    }
    else
    {
        return null;
    }
}

T fromNonNull(T)(NullableTarget!T nonNull) if (isNullable!T)
{
    T res;

    static if (__traits(isSame, TemplateOf!T, Nullable))
    {
        res = nonNull;
    }
    else static if (isPointer!T)
    {
        res = new NullableTarget!T(nonNull);
    }
    else
    {
        res = nonNull;
    }

    return res;
}
