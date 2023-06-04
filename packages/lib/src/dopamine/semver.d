/// Semantic versioning implementation
module dopamine.semver;

@safe:

/// Exception thrown when parsing invalid Semver
class InvalidSemverException : Exception
{
    /// The invalid semver string being parsed
    string semver;
    /// The reason of the parse error
    string reason;

    this(string semver, string reason, string file = __FILE__, size_t line = __LINE__) pure
    {
        import std.format : format;

        super(format("'%s' is not a valid Semantic Version: %s", semver, reason), file, line);
        this.semver = semver;
        this.reason = reason;
    }
}

package size_t indexOrLast(string s, char c) pure
{
    import std.string : indexOf;

    const ind = s.indexOf(c);
    return ind >= 0 ? ind : s.length;
}

/// Semantic version representation
struct Semver
{
    private
    {
        uint _major;
        uint _minor;
        uint _patch;
        string _prerelease;
        string _metadata;
        bool _not_init; // hidden flag to differentiate Semver("0.0.0") from Semver.init
    }

    /// major version
    @property uint major() const pure nothrow @nogc
    {
        return _major;
    }

    /// minor version
    @property uint minor() const pure nothrow @nogc
    {
        return _minor;
    }

    /// patch version
    @property uint patch() const pure nothrow @nogc
    {
        return _patch;
    }

    /// prerelease info
    @property string prerelease() const pure
    {
        return _prerelease;
    }

    /// build metadata
    @property string metadata() const pure
    {
        return _metadata;
    }

    /// Initialize from string representation
    this(string semver) pure
    {
        import std.algorithm : countUntil, min;
        import std.exception : enforce;

        _not_init = true;

        auto input = cast(ByteStr) semver;

        enforce(input.length, new InvalidSemverException(semver, "empty version"));

        auto pos = countUntil(input, '.');
        enforce(pos != -1, new InvalidSemverException(semver, "could not identify major number"));
        auto num = input[0 .. pos];
        input = input[pos + 1 .. $];
        _major = parseNumericIdentifier(num, "major", semver);

        pos = countUntil(input, '.');
        enforce(pos != -1, new InvalidSemverException(semver, "could not identify minor number"));
        num = input[0 .. pos];
        input = input[pos + 1 .. $];
        _minor = parseNumericIdentifier(num, "minor", semver);

        auto dash = countUntil(input, '-');
        if (dash == -1)
            dash = ptrdiff_t.max;
        auto plus = countUntil(input, '+');
        if (plus == -1)
            plus = ptrdiff_t.max;

        num = input[0 .. min($, dash, plus)];
        _patch = parseNumericIdentifier(num, "patch", semver);

        if (dash < plus)
        {
            _prerelease = validatePrerelease(input[dash + 1 .. min($, plus)], semver);
        }
        if (plus < input.length)
        {
            _metadata = validateMetadata(input[plus + 1 .. $], semver);
        }
    }

    /// Initialize from fields
    this(int major, int minor, int patch, string prerelease = null, string metadata = null) pure
    {
        import std.exception : enforce;

        _not_init = true;

        enforce(
            major >= 0 && minor >= 0 && patch >= 0,
            new InvalidSemverException(null, "Major, minor and patch numbers must all be positive")
        );

        _major = major;
        _minor = minor;
        _patch = patch;
        if (prerelease)
            _prerelease = validatePrerelease(cast(ByteStr)prerelease, null);
        if (metadata)
            _metadata = validateMetadata(cast(ByteStr)metadata, null);
    }

    /// ditto
    this(int major, int minor, int patch, string[] prerelease, string[] metadata = null) pure
    {
        import std.array : join;
        import std.exception : enforce;

        _not_init = true;

        enforce(
            major >= 0 && minor >= 0 && patch >= 0,
            new InvalidSemverException(null, "Major, minor and patch numbers must all be positive")
        );

        _major = major;
        _minor = minor;
        _patch = patch;
        if (prerelease)
            _prerelease = validatePrerelease(cast(ByteStr)(prerelease.join('.')), null);
        if (metadata)
            _metadata = validateMetadata(cast(ByteStr)(metadata.join('.')), null);
    }

    /// Semver validation and field matching regular expression recommanded by [semver.org](https://semver.org)
    enum regex = `^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)` ~
        `(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$`;

    static bool isValid(string ver) @safe
    {
        try
        {
            const _ = Semver(ver);
            return true;
        }
        catch (InvalidSemverException)
        {
            return false;
        }
    }

    string toString() const pure @safe
    {
        import std.format : format;

        auto res = format("%s.%s.%s", major, minor, patch);

        if (_prerelease)
        {
            res ~= "-" ~ _prerelease;
        }
        if (_metadata)
        {
            res ~= "+" ~ _metadata;
        }

        return res;
    }

    bool opEquals(const Semver rhs) const pure nothrow @safe
    {
        // metadata is out of the equation
        return _major == rhs._major && _minor == rhs._minor
            && _patch == rhs._patch && _prerelease == rhs._prerelease;
    }

    bool opEquals(const string rhs) const pure
    {
        return opEquals(Semver(rhs));
    }

    size_t toHash() const pure nothrow @safe
    {
        // exclude metadata from hash to be consistent with opEqual
        auto hash = _major.hashOf();
        hash = _minor.hashOf(hash);
        hash = _patch.hashOf(hash);
        return _prerelease.hashOf(hash);
    }

    int opCmp(const Semver rhs) const pure @safe
    {
        import std.algorithm : all, min;
        import std.array : split;
        import std.conv : to;

        // §11.2
        if (_major != rhs._major)
            return _major < rhs._major ? -1 : 1;
        if (_minor != rhs._minor)
            return minor < rhs._minor ? -1 : 1;
        if (_patch != rhs._patch)
            return _patch < rhs._patch ? -1 : 1;

        // §11.3
        const lpr = _prerelease.split('.');
        const rpr = rhs._prerelease.split('.');
        if (lpr && !rpr)
            return -1;
        if (!lpr && rpr)
            return 1;

        // §11.4
        const len = min(lpr.length, rpr.length);
        for (size_t i; i < len; i++)
        {
            const ls = lpr[i];
            const rs = rpr[i];
            const lb = cast(ByteStr)ls;
            const rb = cast(ByteStr)rs;

            if (lb == rb)
                continue;

            const lAllNum = all!isDigit(lb);
            const rAllNum = all!isDigit(rb);

            // §11.4.1
            if (lAllNum && rAllNum)
            {
                try
                {
                    return ls.to!int < rs.to!int ? -1 : 1;
                }
                catch (Exception)
                {
                    assert(false);
                }
            }
            // §11.4.2
            else if (lAllNum == rAllNum) // both false
            {
                return ls < rs ? -1 : 1;
            }
            // §11.4.3
            return lAllNum ? -1 : 1;
        }

        if (lpr.length == rpr.length)
            return 0;

        // §11.4.4
        return lpr.length < rpr.length ? -1 : 1;
    }

    int opCmp(const string rhs) const pure @safe
    {
        return opCmp(Semver(rhs));
    }

    bool opCast(T : bool)() const pure nothrow @safe
    {
        return _not_init;
    }

    Semver opCast(T : Semver)() const pure nothrow @safe
    {
        // const casting is safe because no mutable aliasing
        return this;
    }
}

private alias ByteStr = immutable(ubyte)[];

private uint parseNumericIdentifier(ByteStr num, string field, string semver) pure
{
    import std.algorithm : all;
    import std.conv : to;
    import std.exception : enforce;

    enforce(num.length, new InvalidSemverException(semver, field ~ " is empty"));

    bool leadingZero;

    if (isNumIdent(num, leadingZero))
        return (cast(string) num).to!uint;

    if (leadingZero)
        throw new InvalidSemverException(semver, field ~ " has leading zero");

    throw new InvalidSemverException(semver, field ~ " has non digit character");
}

private string validatePrerelease(ByteStr input, string semver) pure
{
    import std.algorithm : splitter;
    import std.exception : enforce;

    foreach (ident; input.splitter('.'))
    {
        enforce(ident.length, new InvalidSemverException(semver, "prerelease has empty identifier"));

        if (isAlphaNumIdent(ident))
            continue;

        bool leadingZero;
        if (isNumIdent(ident, leadingZero))
            continue;

        if (leadingZero)
            throw new InvalidSemverException(semver, "invalid prerelease (has leading zero)");

        throw new InvalidSemverException(semver, "invalid prerelease");
    }

    return cast(string) input;
}

private string validateMetadata(ByteStr input, string semver) pure
{
    import std.algorithm : all, splitter;
    import std.exception : enforce;

    foreach (ident; input.splitter('.'))
    {
        enforce(ident.length, new InvalidSemverException(semver, "build metadata has empty identifier"));

        if (isAlphaNumIdent(ident))
            continue;

        if (all!isDigit(ident))
            continue;

        throw new InvalidSemverException(semver, "invalid build metadata");
    }

    return cast(string) input;
}

private bool isAlphaNumIdent(ByteStr input) pure
in (input.length > 0)
{
    import std.algorithm : all, any;

    if (isNonDigit(input[0]) && input.length == 1)
        return true;

    if (!all!isIdentChar(input))
        return false;

    return any!isNonDigit(input);
}

private bool isNumIdent(ByteStr input, out bool leadingZero) pure
in (input.length > 0)
{
    import std.algorithm : all;

    if (!all!isDigit(input))
        return false;

    if (input[0] == '0' && input.length > 1)
    {
        leadingZero = true;
        return false;
    }

    return true;
}

private bool isDigit(ubyte c) pure
{
    pragma(inline, true);

    return c >= '0' && c <= '9';
}

private bool isLetter(ubyte c) pure
{
    pragma(inline, true);

    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

private bool isNonDigit(ubyte c) pure
{
    pragma(inline, true);

    return c == '-' || isLetter(c);
}

private bool isIdentChar(ubyte c) pure
{
    pragma(inline, true);

    return isDigit(c) || isNonDigit(c);
}

///
@("Correct Semver parsing")
unittest
{
    const simple = Semver("1.2.3");
    assert(simple.major == 1);
    assert(simple.minor == 2);
    assert(simple.patch == 3);
    assert(!simple.prerelease);
    assert(!simple.metadata);

    const complex = Semver("1.2.34-alpha.1+git.abcdef");
    assert(complex.major == 1);
    assert(complex.minor == 2);
    assert(complex.patch == 34);
    assert(complex.prerelease == "alpha.1");
    assert(complex.metadata == "git.abcdef");

    const metaonly = Semver("1.2.34+git.abcdef");
    assert(metaonly.major == 1);
    assert(metaonly.minor == 2);
    assert(metaonly.patch == 34);
    assert(!metaonly.prerelease);
    assert(metaonly.metadata == "git.abcdef");
}

///
@("Correct Semver parsing errors")
unittest
{
    import std.exception : assertThrown;

    assertThrown!InvalidSemverException(Semver("1"));
    assertThrown!InvalidSemverException(Semver("1.2"));
    assertThrown!InvalidSemverException(Semver("1.2.-3"));
    assertThrown!InvalidSemverException(Semver("1.2.3.4"));
    assertThrown!InvalidSemverException(Semver("1.2a.3"));
    assertThrown!InvalidSemverException(Semver("1.a2.3"));
    assertThrown!InvalidSemverException(Semver("1.2.3-prerel[]"));
    assertThrown!InvalidSemverException(Semver("1.2.3r+meta(bla)"));
    assertThrown!InvalidSemverException(Semver(-1, 2, 3));
}

///
@("Correct Semver to string")
unittest
{
    void check(string semver)
    {
        assert(Semver(semver).toString() == semver);
    }

    check("1.2.3");
    check("1.2.34-alpha.1+git.abcdef");
    check("1.2.34+git.abcdef");
}

///
@("Correct Semver equality")
unittest
{
    assert(Semver("1.2.3") == Semver("1.2.3"));
    assert(Semver("1.2.3-beta") == Semver("1.2.3-beta"));
    assert(Semver("1.2.3") == Semver("1.2.3+meta"));
    assert(Semver("1.2.3-beta") == Semver("1.2.3-beta+meta"));

    assert(Semver("0.2.3") != Semver("1.2.3"));
    assert(Semver("1.1.3") != Semver("1.2.3"));
    assert(Semver("1.2.4") != Semver("1.2.3"));
    assert(Semver("1.2.3-alpha") != Semver("1.2.3-beta"));
}

///
@("Correct Semver comparison")
unittest
{
    assert(Semver("1.0.0") < Semver("2.0.0"));
    assert(Semver("2.0.0") < Semver("2.1.0"));
    assert(Semver("2.1.0") < Semver("2.1.1"));

    assert(Semver("1.0.0-alpha") < Semver("1.0.0"));

    assert(Semver("1.0.0-alpha") < Semver("1.0.0-alpha.1"));
    assert(Semver("1.0.0-alpha.1") < Semver("1.0.0-alpha.beta"));
    assert(Semver("1.0.0-alpha-beta") < Semver("1.0.0-beta"));
    assert(Semver("1.0.0-beta") < Semver("1.0.0-beta.2"));
    assert(Semver("1.0.0-beta.2") < Semver("1.0.0-beta.11"));
    assert(Semver("1.0.0-beta.11") < Semver("1.0.0-rc.1"));
    assert(Semver("1.0.0-rc.1") < Semver("1.0.0"));
}

///
@("Correct Semver cast to bool")
unittest
{
    assert(Semver("1.0.0"));
    assert(Semver("0.0.0"));
    assert(!Semver.init);
}

@("compliant to semver.org valid/invalid versions")
unittest
{
    const validVersions = [
        "0.0.4",
        "1.2.3",
        "10.20.30",
        "1.1.2-prerelease+meta",
        "1.1.2+meta",
        "1.1.2+meta-valid",
        "1.0.0-alpha",
        "1.0.0-beta",
        "1.0.0-alpha.beta",
        "1.0.0-alpha.beta.1",
        "1.0.0-alpha.1",
        "1.0.0-alpha0.valid",
        "1.0.0-alpha.0valid",
        "1.0.0-alpha-a.b-c-somethinglong+build.1-aef.1-its-okay",
        "1.0.0-rc.1+build.1",
        "2.0.0-rc.1+build.123",
        "1.2.3-beta",
        "10.2.3-DEV-SNAPSHOT",
        "1.2.3-SNAPSHOT-123",
        "1.0.0",
        "2.0.0",
        "1.1.7",
        "2.0.0+build.1848",
        "2.0.1-alpha.1227",
        "1.0.0-alpha+beta",
        "1.2.3----RC-SNAPSHOT.12.9.1--.12+788",
        "1.2.3----R-S.12.9.1--.12+meta",
        "1.2.3----RC-SNAPSHOT.12.9.1--.12",
        "1.0.0+0.build.1-rc.10000aaa-kk-0.1",
        // reduced vs semver.org to avoid uint overflow
        "99999999.99999999.99999999",
        "1.0.0-0A.is.legal",
    ];

    const invalidVersions = [
        "1",
        "1.2",
        "1.2.3-0123",
        "1.2.3-0123.0123",
        "1.1.2+.123",
        "+invalid",
        "-invalid",
        "-invalid+invalid",
        "-invalid.01",
        "alpha",
        "alpha.beta",
        "alpha.beta.1",
        "alpha.1",
        "alpha+beta",
        "alpha_beta",
        "alpha.",
        "alpha..",
        "beta",
        "1.0.0-alpha_beta",
        "-alpha.",
        "1.0.0-alpha..",
        "1.0.0-alpha..1",
        "1.0.0-alpha...1",
        "1.0.0-alpha....1",
        "1.0.0-alpha.....1",
        "1.0.0-alpha......1",
        "1.0.0-alpha.......1",
        "01.1.1",
        "1.01.1",
        "1.1.01",
        "1.2",
        "1.2.3.DEV",
        "1.2-SNAPSHOT",
        "1.2.31.2.3----RC-SNAPSHOT.12.09.1--..12+788",
        "1.2-RC-SNAPSHOT",
        "-1.0.3-gamma+b7718",
        "+justmeta",
        "9.8.7+meta+meta",
        "9.8.7-whatever+meta+meta",
        // reduced vs semver.org to avoid uint overflow
        "99999999.99999999.99999999----RC-SNAPSHOT.12.09.1-----------------------------..12",
    ];

    foreach (ver; validVersions)
        assert(Semver.isValid(ver), ver ~ " should be valid");

    foreach (ver; invalidVersions)
        assert(!Semver.isValid(ver), ver ~ " should not be valid");
}
