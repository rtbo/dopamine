/// Semantic vertioning implementation
module dopamine.semver;

@safe:

/// Exception thrown when parsing invalid Semver
class SemverParseException : Exception
{
    /// The semver string being parsed
    string semver;

    this(string semver, string msg) pure
    {
        import std.format : format;

        this.semver = semver;
        super(format("'%s' is not a valid Semantic Version: %s", semver, msg));
    }
}

/// Semantic version representation
struct Semver
{
    /// major version
    int major;
    /// minor version
    int minor;
    /// patch version
    int patch;
    /// prerelease info
    string[] prerelease;
    /// build metadata
    string[] metadata;

    this(string semver) pure
    {
        import std.algorithm : min;
        import std.conv : ConvException, to;
        import std.format : format;
        import std.exception : assumeUnique, enforce;
        import std.string : split;

        const hyp = indexOrLast(semver, '-');
        const plus = indexOrLast(semver, '+');

        enforce(hyp == semver.length || hyp <= plus,
                new SemverParseException(semver, "metadata MUST come last"));

        const main = semver[0 .. min(hyp, plus)].split('.');

        enforce(main.length == 3, new SemverParseException(semver,
                "Expected 3 parts in main section"));
        try
        {
            this.major = main[0].to!int;
            this.minor = main[1].to!int;
            this.patch = main[2].to!int;
        }
        catch (ConvException ex)
        {
            throw new SemverParseException(semver, ex.msg);
        }

        if (hyp < semver.length)
        {
            const prerelease = semver[hyp + 1 .. plus];
            enforce(prerelease.length > 0, new SemverParseException(semver,
                    "Pre-release section may not be empty"));
            enforce(allValidChars(prerelease, true), new SemverParseException(semver,
                    "Pre-release section contain invalid character"));
            this.prerelease = prerelease.split('.');
        }

        if (plus < semver.length)
        {
            const metadata = semver[plus + 1 .. $];
            enforce(metadata.length > 0, new SemverParseException(semver,
                    "Build-metadata section may not be empty"));
            enforce(allValidChars(metadata, true), new SemverParseException(semver,
                    "Pre-release section contain invalid character"));
            this.metadata = metadata.split('.');
        }
    }

    invariant()
    {
        import std.algorithm : all;

        assert(major >= 0, "major must be positive");
        assert(minor >= 0, "minor must be positive");
        assert(patch >= 0, "patch must be positive");
        assert(prerelease.all!(s => allValidChars(s, false)),
                "prerelease contain invalid characters");
        assert(metadata.all!(s => allValidChars(s, false)), "metadata contain invalid characters");
    }

    string toString() const pure
    {
        import std.format : format;
        import std.string : join;

        auto res = format("%s.%s.%s", major, minor, patch);

        if (prerelease)
        {
            res ~= "-" ~ prerelease.join(".");
        }
        if (metadata)
        {
            res ~= "+" ~ metadata.join(".");
        }

        return res;
    }

    bool opEquals(const Semver rhs) const pure
    {
        // metadata is out of the equation
        return major == rhs.major && minor == rhs.minor && patch == rhs.patch
            && prerelease == rhs.prerelease;
    }

    int opCmp(const Semver rhs) const pure
    {
        import std.algorithm : min;
        import std.conv : to;

        // §11.2
        if (major != rhs.major)
            return major < rhs.major ? -1 : 1;
        if (minor != rhs.minor)
            return minor < rhs.minor ? -1 : 1;
        if (patch != rhs.patch)
            return patch < rhs.patch ? -1 : 1;

        // §11.3
        if (prerelease && !rhs.prerelease)
            return -1;
        if (!prerelease && rhs.prerelease)
            return 1;

        // §11.4
        const len = min(prerelease.length, rhs.prerelease.length);
        for (size_t i; i < len; i++)
        {
            const l = prerelease[i];
            const r = rhs.prerelease[i];

            if (l == r)
                continue;

            const lAllNum = allNum(l);
            const rAllNum = allNum(r);

            // §11.4.1
            if (lAllNum && rAllNum)
            {
                return l.to!int < r.to!int ? -1 : 1;
            }
            // §11.4.2
            else if (lAllNum == rAllNum) // both false
            {
                return l < r ? -1 : 1;
            }
            // §11.4.3
            return lAllNum ? -1 : 1;
        }

        if (prerelease.length == rhs.prerelease.length)
            return 0;

        // §11.4.4
        return prerelease.length < rhs.prerelease.length ? -1 : 1;
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
    assert(complex.prerelease == ["alpha", "1"]);
    assert(complex.metadata == ["git", "abcdef"]);

    const metaonly = Semver("1.2.34+git.abcdef");
    assert(metaonly.major == 1);
    assert(metaonly.minor == 2);
    assert(metaonly.patch == 34);
    assert(!metaonly.prerelease);
    assert(metaonly.metadata == ["git", "abcdef"]);
}

///
@("Correct Semver parsing errors")
unittest
{
    import std.exception : assertThrown;

    assertThrown!SemverParseException(Semver("1"));
    assertThrown!SemverParseException(Semver("1.2"));
    assertThrown!SemverParseException(Semver("1.2.3.4"));
    assertThrown!SemverParseException(Semver("1.2a.3"));
    assertThrown!SemverParseException(Semver("1.a2.3"));
    assertThrown!SemverParseException(Semver("1.2.3+meta-prerel"));
    assertThrown!SemverParseException(Semver("1.2.3-prerel[]"));
    assertThrown!SemverParseException(Semver("1.2.3r+meta(bla)"));
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

private:

size_t indexOrLast(string s, char c) pure
{
    import std.string : indexOf;

    const ind = s.indexOf(c);
    return ind >= 0 ? ind : s.length;
}

bool allValidChars(string s, bool allowDot = false) pure
{
    foreach (c; s)
    {
        const ascii = cast(int) c;
        if (ascii >= cast(int) 'a' && ascii <= cast(int) 'z')
            continue;
        if (ascii >= cast(int) 'A' && ascii <= cast(int) 'Z')
            continue;
        if (ascii >= cast(int) '0' && ascii <= cast(int) '9')
            continue;
        if (c == '-')
            continue;
        if (allowDot && c == '.')
            continue;

        return false;
    }

    return true;
}

bool allNum(string s) pure
{
    foreach (c; s)
    {
        const ascii = cast(int) c;
        if (ascii < cast(int) '0' || ascii > cast(int) '9')
            return false;
    }
    return true;
}
