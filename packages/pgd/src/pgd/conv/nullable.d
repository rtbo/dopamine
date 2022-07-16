module pgd.conv.nullable;

import pgd.maybe;

import std.traits;
import std.typecons;

template isNullable(T)
{
    enum isNullable = isInstanceOf!(Nullable, T) || isInstanceOf!(MayBe, T) || isPointer!T;
}

template NullableTarget(T)
{
    static if (isInstanceOf!(Nullable, T))
    {
        alias NullableTarget = typeof(T.init.get());
    }
    else static if (isInstanceOf!(MayBe, T))
    {
        alias NullableTarget = MayBeTarget!T;
    }
    else static if (isPointer!T)
    {
        alias NullableTarget = PointerTarget!T;
    }
    else
    {
        alias NullableTarget = void;
    }
}

static assert(isNullable!(int*));
static assert(isNullable!(Nullable!int));
static assert(isNullable!(MayBe!(string, null)));
static assert(!isNullable!(string));
static assert(!isNullable!(ubyte[]));
static assert(!isNullable!(ubyte[32]));
static assert(is(NullableTarget!(int*) == int));
static assert(is(NullableTarget!(Nullable!int) == int));
static assert(is(NullableTarget!(string) == void));

bool isNull(T)(T maybe) if (isNullable!T)
{
    static if (isInstanceOf!(Nullable, T))
    {
        return maybe.isNull;
    }
    else static if (isInstanceOf!(MayBe, T))
    {
        return !maybe.valid;
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
    static if (isInstanceOf!(Nullable, T))
    {
        return val.get;
    }
    else static if (isInstanceOf!(MayBe, T))
    {
        return val.value;
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
    static if (isInstanceOf!(Nullable, T))
    {
        return T.init;
    }
    else static if (isInstanceOf!(MayBe, T))
    {
        return T.init;
    }
    else static if (isPointer!T)
    {
        return null;
    }
}

T fromNonNull(T)(NullableTarget!T nonNull) if (isNullable!T)
{
    T res;

    static if (isInstanceOf!(Nullable, T))
    {
        res = nonNull;
    }
    else static if (isInstanceOf!(MayBe, T))
    {
        res = nonNull;
    }
    else static if (isPointer!T)
    {
        res = new NullableTarget!T(nonNull);
    }

    return res;
}
