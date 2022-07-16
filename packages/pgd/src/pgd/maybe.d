/// This module defines MayBe and related utilities.
/// MayBe is semantically the same as std.typecons.Nullable, but has
/// better range interoperability and less compatibility with corner cases.
module pgd.maybe;

import std.exception;
import std.range;

/// Stores may be a instance of T, and a boolean
struct MayBe(T)
{
    private T _value;
    private bool _valid;

    private this (T value, bool valid)
    {
        _value = value;
        _valid = valid;
    }

    /// construct a valid instance
    this(T value)
    {
        _value = value;
        _valid = true;
    }

    @property T value() const
    {
        enforce(_valid, "instance is not valid");
        return _value;
    }

    @property bool valid() const
    {
        return _valid;
    }

    /// Make this object invalid.
    void invalidate()
    {
        _value = T.init;
        _valid = false;
    }

    void opAssign(T val)
    {
        _value = val;
        _valid = true;
    }

    /// range interface
    @property bool empty() const
    {
        return !valid;
    }

    /// ditto
    @property T front() const
    {
        return value;
    }

    /// ditto
    void popFront()
    {
        invalidate();
    }

    /// ditto
    MayBe!T save() const
    {
        return MayBe!T(_value, _valid);
    }

    /// ditto
    @property T back() const
    {
        return value;
    }

    /// ditto
    void popBack()
    {
        invalidate();
    }

    /// ditto
    @property size_t length() const
    {
        return _valid ? 1 : 0;
    }

    /// ditto
    @property size_t opDollar() const
    {
        return _valid ? 1 : 0;
    }

    /// ditto
    @property T opIndex(size_t index) const
    {
        enforce(_valid && index == 0, "instance is not valid or index out of bounds");
        return _value;
    }
}

@("MayBe")
unittest
{
    import std.algorithm;
    import std.array;

    MayBe!int mb1;

    assert(!mb1.valid);
    assert(mb1.length == 0);
    assert(mb1.empty);
    assertThrown(mb1.value);
    assertThrown(mb1.front);
    assertThrown(mb1.back);
    assertThrown(mb1[0]);

    mb1 = 1;

    assert(mb1.valid);
    assert(mb1.length == 1);
    assert(!mb1.empty);
    assert(mb1.value == 1);
    assert(mb1.front == 1);
    assert(mb1.back == 1);
    assert(mb1[0] == 1);

    mb1.invalidate();

    assert(!mb1.valid);

    mb1 = 1;
    const arr = mb1.map!(i => i * 2).array;
    assert(arr == [2]);
}

/// Stores an instance of T and use "invalidValue" as invalid state indicator
struct MayBe(T, T invalidValue)
{
    private T _value = invalidValue;

    this(T value)
    {
        _value = value;
    }

    @property T value() const
    {
        enforce(valid, "instance is not valid");
        return _value;
    }

    @property bool valid() const
    {
        return _value != invalidValue;
    }

    /// Make this object invalid.
    void invalidate()
    {
        _value = invalidValue;
    }

    void opAssign(T val)
    {
        _value = val;
    }

    /// range interface
    @property bool empty() const
    {
        return !valid;
    }

    /// ditto
    @property T front() const
    {
        return value;
    }

    /// ditto
    void popFront()
    {
        invalidate();
    }

    /// ditto
    MayBe!(T, invalidValue) save() const
    {
        return MayBe!(T, invalidValue)(_value);
    }

    /// ditto
    @property T back() const
    {
        return value;
    }

    /// ditto
    void popBack()
    {
        invalidate();
    }

    /// ditto
    @property size_t length() const
    {
        return valid ? 1 : 0;
    }

    /// ditto
    @property size_t opDollar() const
    {
        return valid ? 1 : 0;
    }

    /// ditto
    @property T opIndex(size_t index) const
    {
        enforce(valid && index == 0, "instance is not valid or index out of bounds");
        return _value;
    }
}

@("MayBe with invalidValue")
unittest
{
    import std.algorithm;
    import std.array;

    MayBe!(int, -1) mb;

    assert(mb._value == -1);
    assert(!mb.valid);
    assert(mb.length == 0);
    assert(mb.empty);
    assertThrown(mb.value);
    assertThrown(mb.front);
    assertThrown(mb.back);
    assertThrown(mb[0]);

    mb = 0;

    assert(mb.valid);
    assert(mb.length == 1);
    assert(!mb.empty);
    assert(mb.value == 0);
    assert(mb.front == 0);
    assert(mb.back == 0);
    assert(mb[0] == 0);

    mb.invalidate();

    assert(!mb.valid);

    mb = 1;
    const arr = mb.map!(i => i * 2).array;
    assert(arr == [2]);
}

/// Construct a valid MayBe value
MayBe!T mayBe(T)(T value) if (!isInputRange!T)
{
    return MayBe!T(value);
}

/// Construct an invalid mayBe value
MayBe!T mayBe(T)() if (!isInputRange!T)
{
    return MayBe!T(T.init, false);
}

@("mayBe")
unittest
{
    const mb = mayBe!int();
    const mb1 = mayBe(12);

    assert(!mb.valid);
    assert(mb1.valid && mb1.value == 12);
}

/// Construct a may be valid MayBe valid.
/// validity depends on the invalidValue template parameter
MayBe!(T, invalidValue) mayBe(T, T invalidValue)(T value = invalidValue)
{
    return MayBe!(T, invalidValue)(value);
}

@("mayBe with invalidValue")
unittest
{
    const mb = mayBe!(int, -1)();
    const mb1 = mayBe!(int, -1)(12);
    const mb2 = mayBe!(int, -1)(-1);

    assert(!mb.valid);
    assert(mb1.valid && mb1.value == 12);
    assert(!mb2.valid);
}

/// Construct a MayBe value from a range.
/// The returned value is valid if the range has one element
/// Throws if the range has more than one element
auto mayBe(I)(I input) if (isInputRange!I)
{
    alias T = ElementType!I;

    MayBe!T res;

    if (!input.empty)
    {
        res = MayBe!T(input.front);

        input.popFront();
        enforce(input.empty, "Range provided to mayBe must have one or zero element");
    }

    return res;
}

@("mayBe with range")
unittest
{
    import std.algorithm;

    MayBe!int mb;
    MayBe!int mb1 = 1;
    int[] arr0 = [];
    int[] arr1 = [1];
    int[] arr2 = [1, 2];

    MayBe!int mbBis = mb.map!(i => i * 2).mayBe();
    MayBe!int mb1Bis = mb1.map!(i => i * 2).mayBe();
    MayBe!int arr0Bis = arr0.map!(i => i * 2).mayBe();
    MayBe!int arr1Bis = arr1.map!(i => i * 2).mayBe();
    assertThrown(arr2.map!(i => i * 2).mayBe());

    assert(!mbBis.valid);
    assert(mb1Bis.valid && mb1Bis.value == 2);
    assert(!arr0Bis.valid);
    assert(arr1Bis.valid && arr1Bis.value == 2);
}
