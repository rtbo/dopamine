module dopamine.dependency;

import dopamine.semver;

import std.exception;
import std.string;

/// Exception thrown when parsing invalid Version Specification
class InvalidVersionSpecException : Exception
{
    /// The invalid spec being parsed
    string spec;
    /// The reason of the parse error
    string reason;

    this(string spec, string reason)
    {
        super(format("'%s': invalid version specification - %s", spec, reason));
        this.spec = spec;
        this.reason = reason;
    }
}

/// Dependency version specification
struct VersionSpec
{
    private
    {
        Semver _lower;
        bool _lowerIncluded = true;
        Semver _upper;
        bool _upperIncluded;
    }

    /// Initialize version specification.
    /// Semantics are compatible with DUB
    this(in string spec)
    {
        enforce(spec.length, new InvalidVersionSpecException(spec, "Cannot be empty"));

        try
        {
            if (spec == "*")
            {
                // special "match-all" upper check when includeUpper is true and upper == Semver.init
                _upperIncluded = true;
            }
            else if (spec.startsWith("~>"))
            {
                size_t comps;
                const s = expandMainSection(spec[2 .. $], &comps);

                enforce(comps == 2 || comps == 3,
                        spec ~ " is not a valid dependency version specification");

                _lower = Semver(s);

                if (comps == 2)
                {
                    _upper = Semver(_lower.major + 1, 0, 0, ["0"]);
                }
                else
                {
                    _upper = Semver(_lower.major, _lower.minor + 1, 0, ["0"]);
                }
            }
            else if (spec.startsWith("^"))
            {
                size_t comps;
                const s = expandMainSection(spec[1 .. $], &comps);

                enforce(comps == 2 || comps == 3,
                        spec ~ " is not a valid dependency version specification");

                _lower = Semver(s);
                if (_lower.major == 0)
                {
                    // if lower prerelease, upper will still be compatible with release
                    _upper = Semver(_lower.major, _lower.minor, _lower.patch);
                    _upperIncluded = true;
                }
                else
                {
                    _upper = Semver(_lower.major + 1, 0, 0, ["0"]);
                }
            }
            else if (spec.startsWith("=="))
            {
                size_t comps;
                const s = expandMainSection(spec[2 .. $], &comps);

                _lower = Semver(s);
                _upper = _lower;
                _upperIncluded = true;
            }
            else if (spec.startsWith(">"))
            {
                import dopamine.util : indexOrLast;

                enforce(spec.length > 1, new InvalidVersionSpecException(spec, "Empty version"));

                _lowerIncluded = spec[1] == '=';
                size_t beg = _lowerIncluded ? 2 : 1;

                const end = beg + indexOrLast(spec[beg .. $], ' ');
                _lower = Semver(expandMainSection(spec[beg .. end]));

                if (end < spec.length)
                {
                    beg = end + 1; // eat space
                    // eat more space if any
                    while (spec[beg] == ' ')
                        beg++;

                    enforce(spec.length > beg + 1, new InvalidVersionSpecException(spec,
                            "expected upper version bound"));
                    enforce(spec[beg] == '<', new InvalidVersionSpecException(spec,
                            format("expected upper version bound but got '%s'", spec[beg])));

                    beg += 1;
                    if (spec[beg] == '=')
                    {
                        beg++;
                        _upperIncluded = true;
                    }
                    _upper = Semver(expandMainSection(spec[beg .. $]));
                }
                else
                {
                    // upper initialized to Semver.init , which is interpreted as match-all when _upperIncluded is true
                    _upperIncluded = true;
                }
            }
            else if (spec.startsWith("<"))
            {
                // lower initialized to Semver.init , which will match all versions

                enforce(spec.length > 1, new InvalidVersionSpecException(spec, "Empty version"));

                _upperIncluded = spec[1] == '=';
                const beg = _upperIncluded ? 2 : 1;
                _upper = Semver(spec[beg .. $]);
            }
            else if (spec[0] >= '0' && spec[0] <= '9')
            {
                _lower = Semver(expandMainSection(spec));
                _upper = _lower;
                _upperIncluded = true;
            }
            else
            {
                throw new InvalidVersionSpecException(spec, "invalid start of specification");
            }
        }
        catch (InvalidSemverException ex)
        {
            throw new InvalidVersionSpecException(spec,
                    format("Could not parse version '%s': %s", ex.semver, ex.reason));
        }
    }

    @property const(Semver) lower() const nothrow pure
    {
        return _lower;
    }

    @property bool lowerIncluded() const nothrow pure
    {
        return _lowerIncluded;
    }

    @property const(Semver) upper() const nothrow pure
    {
        return _upper;
    }

    @property bool upperIncluded() const nothrow pure
    {
        return _upperIncluded;
    }

    bool matchVersion(const(Semver) ver) const nothrow pure
    {
        // disallow prerelease if none was specified
        if (!_lower.prerelease && ver.prerelease)
            return false;

        const lowerTest = _lower.opCmp(ver);
        if (lowerTest > 0)
            return false;
        if (lowerTest == 0 && !_lowerIncluded)
            return false;

        // lower passed, checking upper

        // special check if upper = Semver.init and _upperIncluded is true
        if (_upperIncluded && _upper == Semver.init)
            return true;

        const upperTest = _upper.opCmp(ver);
        if (upperTest > 0)
            return true;
        return upperTest == 0 && _upperIncluded;
    }

    bool matchVersion(string semver) const pure
    {
        return matchVersion(Semver(semver));
    }
}

///
@("VersionSpec works as intended")
unittest
{
    assert(!VersionSpec.init.matchVersion("0.0.0"));
    assert(!VersionSpec.init.matchVersion("1.0.0"));

    assert(VersionSpec("*").matchVersion("0.0.0"));
    assert(VersionSpec("*").matchVersion("99.9.9"));

    assert(VersionSpec("~>1.2.3").matchVersion("1.2.3"));
    assert(VersionSpec("~>1.2.3").matchVersion("1.2.9"));
    assert(!VersionSpec("~>1.2.3").matchVersion("1.2.2"));
    assert(!VersionSpec("~>1.2.3").matchVersion("1.1.9"));
    assert(!VersionSpec("~>1.2.3").matchVersion("1.3.0"));
    assert(!VersionSpec("~>1.2.3").matchVersion("2.0.0"));
    assert(!VersionSpec("~>1.2.3").matchVersion("1.2.3-beta"));

    assert(VersionSpec("~>1.2").matchVersion("1.2.0"));
    assert(VersionSpec("~>1.2").matchVersion("1.2.9"));
    assert(VersionSpec("~>1.2").matchVersion("1.9.99"));
    assert(!VersionSpec("~>1.2").matchVersion("1.1.9"));
    assert(!VersionSpec("~>1.2").matchVersion("0.9.9"));
    assert(!VersionSpec("~>1.2").matchVersion("2.0.0"));
    assert(!VersionSpec("~>1.2").matchVersion("1.2.0-beta"));

    assert(VersionSpec("^1.2.3").matchVersion("1.2.3"));
    assert(VersionSpec("^1.2.3").matchVersion("1.2.9"));
    assert(VersionSpec("^1.2.3").matchVersion("1.9.9"));
    assert(!VersionSpec("^1.2.3").matchVersion("1.2.2"));
    assert(!VersionSpec("^1.2.3").matchVersion("2.0.0"));
    assert(!VersionSpec("^1.2.3").matchVersion("1.2.3-beta"));

    assert(VersionSpec("^0.1.2").matchVersion("0.1.2"));
    assert(!VersionSpec("^0.1.2").matchVersion("0.1.3"));

    assert(VersionSpec(">=1.2.3").matchVersion("1.2.3"));
    assert(VersionSpec(">=1.2.3").matchVersion("5.0.0"));
    assert(!VersionSpec(">=1.2.3").matchVersion("5.0.0-beta"));

    assert(!VersionSpec(">1.2.3").matchVersion("1.2.3"));
    assert(VersionSpec(">1.2.3").matchVersion("5.0.0"));
    assert(!VersionSpec(">1.2.3").matchVersion("5.0.0-beta"));

    assert(VersionSpec(">=1.2.3 <3.0.0").matchVersion("1.2.3"));
    assert(VersionSpec(">=1.2.3 <3.0.0").matchVersion("2.0.0"));
    assert(!VersionSpec(">=1.2.3 <3.0.0").matchVersion("5.0.0"));
    assert(!VersionSpec(">=1.2.3 <3.0.0").matchVersion("3.0.0"));
    assert(VersionSpec(">=1.2.3 <=3.0.0").matchVersion("3.0.0"));

    assert(VersionSpec("<=1.2.3").matchVersion("1.2.3"));
    assert(VersionSpec("<=1.2.3").matchVersion("1.2.2"));
    assert(!VersionSpec("<=1.2.3").matchVersion("1.2.4"));

    assert(!VersionSpec("<1.2.3").matchVersion("1.2.3"));
    assert(VersionSpec("<1.2.3").matchVersion("1.2.2"));
    assert(!VersionSpec("<1.2.3").matchVersion("1.2.4"));

    assert(VersionSpec("1.2.3").matchVersion("1.2.3"));
    assert(!VersionSpec("1.2.3").matchVersion("1.2.4"));
    assert(!VersionSpec("1.2.3").matchVersion("1.2.2"));
    assert(!VersionSpec("1.2.3").matchVersion("1.2.3-beta"));
}

private:

// [major, (minor), (patch)]
string[] mainSection(string ver, size_t* outEnd = null)
{
    size_t end = ver.length;
    foreach (i, c; ver)
    {
        if (c == '-' || c == '+' || c == ' ')
        {
            end = i;
            break;
        }
    }

    if (outEnd)
        *outEnd = end;
    return ver[0 .. end].split(".");
}

/// Complete main section of a version so that it has 3 components
string expandMainSection(string ver, size_t* numComps = null)
{
    size_t end = ver.length;
    size_t dots;
    foreach (i, c; ver)
    {
        if (c == '.')
            dots++;
        if (c == '-' || c == '+' || c == ' ')
        {
            end = i;
            break;
        }
    }

    enforce(dots <= 2, format("'%s' is not a valid version spec"));

    if (numComps)
        *numComps = dots + 1;

    if (dots == 2)
        return ver;

    const compl = dots == 1 ? ".0" : ".0.0";
    return ver[0 .. end] ~ compl ~ ver[end .. $];
}
