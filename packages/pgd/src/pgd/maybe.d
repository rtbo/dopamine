/// This module defines MayBe and related utilities.
/// MayBe is a generic utility that is semantically identical to std.typecons.Nullable, but has
/// better range interoperability and probably less compatibility with corner cases.
///
/// MayBe can be used with PGD to map to nullable column values.
module pgd.maybe;

import std.datetime.systime;
import std.exception;
import std.range;
import std.traits;

@safe:

/// Stores may be a instance of T, and a boolean
struct MayBe(T)
{
    private T _value;
    private bool _valid;

    private this(T value, bool valid)
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

    this(MayBe!T mb)
    {
        _value = mb._value;
        _valid = mb._valid;
    }

    this(typeof(null))
    {
        _value = T.init;
        _valid = false;
    }

    @property T value() const
    {
        enforce(_valid, "instance is not valid");
        return _value;
    }

    T valueOr(lazy T def) const
    {
        return _valid ? _value : def;
    }

    @property bool valid() const
    {
        return _valid;
    }

    @property bool opCast(T : bool)() const
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

    void opAssign(typeof(null))
    {
        invalidate();
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

    MayBe!int mb;

    assert(!mb.valid);
    assert(mb.length == 0);
    assert(mb.empty);
    assertThrown(mb.value);
    assertThrown(mb.front);
    assertThrown(mb.back);
    assertThrown(mb[0]);

    mb = 1;

    assert(mb.valid);
    assert(mb.length == 1);
    assert(!mb.empty);
    assert(mb.value == 1);
    assert(mb.front == 1);
    assert(mb.back == 1);
    assert(mb[0] == 1);

    mb.invalidate();

    assert(!mb.valid);

    mb = 1;
    const arr = mb.map!(i => i * 2).array;
    assert(arr == [2]);

    mb = 1;
    mb = null;
    assert(!mb.valid);
}

/// Stores an instance of T and use "invalidValue" as invalid state indicator
struct MayBe(T, T invalidValue)
{
    private T _value = invalidValue;

    this(T value)
    {
        _value = value;
    }

    this(MayBe!(T, invalidValue) mb)
    {
        _value = mb._value;
    }

    this(typeof(null))
    {
        _value = invalidValue;
    }

    @property T value() const
    {
        enforce(valid, "instance is not valid");
        return _value;
    }

    T valueOr(lazy T def) const
    {
        return _value != invalidValue ? _value : def;
    }

    @property bool valid() const
    {
        return _value != invalidValue;
    }

    @property bool opCast(T : bool)() const
    {
        return valid;
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

    void opAssign(typeof(null))
    {
        invalidate();
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

    mb = 1;
    mb = null;
    assert(!mb.valid);
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
// MayBe!(T, invalidValue) mayBe(T, T invalidValue)(T value = invalidValue)
//         if (!isInputRange!T)
// {
//     return MayBe!(T, invalidValue)(value);
// }

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

template mayBe(T, T invalidValue)
{
    MayBe!(T, invalidValue) mayBe(T value = invalidValue)
    {
        return MayBe!(T, invalidValue)(value);
    }

    /// Construct a MayBe value from a range where an invalid value is represented by invalidValue.
    /// The returned value is valid if the range has one element
    /// Throws if the range has more than one element or if the range yields invalidValue.
    auto mayBe(I)(I input) if (isInputRange!I)
    {
        MayBe!(T, invalidValue) res;

        if (!input.empty)
        {
            auto val = input.front;

            enforce(val != invalidValue, "Range returned invalidValue");

            res = val;
            input.popFront();
            enforce(input.empty, "Range provided to mayBe must have one or zero element");
        }

        return res;
    }
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

@("mayBe with range and string")
unittest
{
    import std.algorithm;
    import std.string;

    MayBeText mb;
    MayBeText mbs = "hello";
    string[] arr0 = [];
    string[] arr1 = ["hello"];
    string[] arr2 = ["hello", "hollo"];

    MayBeText mbBis = mb.map!(s => s.toUpper())
        .mayBeText();
    MayBeText mbsBis = mbs.map!(s => s.toUpper())
        .mayBeText();
    MayBeText arr0Bis = arr0.map!(s => s.toUpper())
        .mayBeText();
    MayBeText arr1Bis = arr1.map!(s => s.toUpper())
        .mayBeText();
    assertThrown(arr2.map!(s => s.toUpper())
            .mayBeText());

    assert(!mbBis.valid);
    assert(mbsBis.valid && mbsBis.value == "HELLO");
    assert(!arr0Bis.valid);
    assert(arr1Bis.valid && arr1Bis.value == "HELLO");
}

/// Type suitable to map to Postgres nullable text column
alias MayBeText = MayBe!(string, null);

/// ditto
alias mayBeText = mayBe!(string, null);

/// Type suitable to map to Postgres nullable timestamptz column
alias MayBeTimestamp = MayBe!(SysTime, SysTime.init);

/// ditto
alias mayBeTimestamp = mayBe!(SysTime, SysTime.init);

/// Get the type targetted by MB
template MayBeTarget(MB) if (isInstanceOf!(MayBe, MB))
{
    alias MayBeTarget = typeof(MB.init.value);
}

static assert(is(MayBeTarget!(MayBe!int) == int));
static assert(is(MayBeTarget!MayBeText == string));
static assert(is(MayBeTarget!MayBeTimestamp == SysTime));
