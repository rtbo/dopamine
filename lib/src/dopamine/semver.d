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

    this(string semver, string reason) pure
    {
        import std.format : format;

        super(format("'%s' is not a valid Semantic Version: %s", semver, reason));
        this.semver = semver;
        this.reason = reason;
    }
}

/// Semantic version representation
struct Semver
{
    private
    {
        int _major;
        int _minor;
        int _patch;
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
        import dopamine.util : indexOrLast;

        import std.algorithm : min, canFind;
        import std.conv : ConvException, to;
        import std.format : format;
        import std.exception : assumeUnique, enforce;
        import std.string : split;

        _not_init = true;

        const hyp = indexOrLast(semver, '-');
        const plus = indexOrLast(semver, '+');

        enforce(hyp == semver.length || hyp <= plus,
            new InvalidSemverException(semver, "metadata MUST come last"));

        const main = semver[0 .. min(hyp, plus)].split('.');

        enforce(main.length == 3, new InvalidSemverException(semver,
                "Expected 3 parts in main section"));
        try
        {
            _major = main[0].to!int;
            _minor = main[1].to!int;
            _patch = main[2].to!int;
        }
        catch (ConvException ex)
        {
            throw new InvalidSemverException(semver, ex.msg);
        }

        if (hyp < semver.length)
        {
            _prerelease = semver[hyp + 1 .. plus];
            enforce(_prerelease.length > 0, new InvalidSemverException(semver,
                    "Pre-release section may not be empty"));
            enforce(!_prerelease.canFind(".."), new InvalidSemverException(semver,
                    "Pre-release subsection may not be empty"));
            enforce(allValidChars(_prerelease, true), new InvalidSemverException(semver,
                    "Pre-release section contain invalid character"));
        }

        if (plus < semver.length)
        {
            _metadata = semver[plus + 1 .. $];
            enforce(_metadata.length > 0, new InvalidSemverException(semver,
                    "Build-metadata section may not be empty"));
            enforce(!_metadata.canFind(".."), new InvalidSemverException(semver,
                    "Bulid-metadata subsection may not be empty"));
            enforce(allValidChars(_metadata, true), new InvalidSemverException(semver,
                    "Build-metadata section contain invalid character"));
        }
    }

    /// Initialize from fields
    this(int major, int minor, int patch, string[] prerelease = null, string[] metadata = null) pure
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
        _prerelease = prerelease.join('.');
        _metadata = metadata.join('.');
    }

    invariant ()
    {
        import std.algorithm : all, canFind;

        assert(_major >= 0, "major must be positive");
        assert(_minor >= 0, "minor must be positive");
        assert(_patch >= 0, "patch must be positive");
        assert(allValidChars(_prerelease, true), "prerelease contain invalid characters");
        assert(!_prerelease.canFind(".."), "prerelease contain empty subsection");
        assert(allValidChars(_metadata, true), "metadata contain invalid characters");
        assert(!_metadata.canFind(".."), "metadata contain empty subsection");
    }

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
        import std.string : join;

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
        // exclude metadata from hash to be consiste with opEqual
        auto hash = _major.hashOf();
        hash = _minor.hashOf(hash);
        hash = _patch.hashOf(hash);
        return _prerelease.hashOf(hash);
    }

    int opCmp(const Semver rhs) const pure @safe
    {
        import std.algorithm : min;
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
            const l = lpr[i];
            const r = rpr[i];

            if (l == r)
                continue;

            const lAllNum = allNum(l);
            const rAllNum = allNum(r);

            // §11.4.1
            if (lAllNum && rAllNum)
            {
                try
                {
                    return l.to!int < r.to!int ? -1 : 1;
                }
                catch (Exception)
                {
                    assert(false);
                }
            }
            // §11.4.2
            else if (lAllNum == rAllNum) // both false
            {
                return l < r ? -1 : 1;
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
    assertThrown!InvalidSemverException(Semver("1.2.3+meta-prerel"));
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

private:

bool allValidChars(string s, bool allowDot = false) pure
{
    foreach (c; s)
    {
        if (c >= 'a' && c <= 'z')
            continue;
        if (c >= 'A' && c <= 'Z')
            continue;
        if (c >= '0' && c <= '9')
            continue;
        if (c == '-')
            continue;
        if (allowDot && c == '.')
            continue;

        return false;
    }

    return true;
}

bool allNum(string s) pure nothrow
{
    foreach (c; s)
    {
        const ascii = cast(int) c;
        if (ascii < cast(int) '0' || ascii > cast(int) '9')
            return false;
    }
    return true;
}
