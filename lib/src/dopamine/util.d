module dopamine.util;

import std.digest;
import std.file;
import std.string;
import std.traits;

@safe:

package:

/// Check if array has duplicates
/// Will try first as if the array is sorted
/// and will fallback to brute force if not
bool hasDuplicates(T)(const(T)[] arr) if (!is(T == class))
{
    if (arr.length <= 1)
        return false;

    T last = arr[0];
    foreach (el; arr[1 .. $])
    {
        if (last == el)
            return true;
        if (last < el)
        {
            last = el;
            continue;
        }
        // not sorted: alternative impl
        foreach (i, a; arr[0 .. $ - 1])
        {
            foreach (b; arr[i + 1 .. $])
            {
                if (a == b)
                    return true;
            }
        }
        break;
    }
    return false;
}

/// Generate a unique name for temporary path (either dir or file)
/// Params:
///     location = some directory to place the file in. If omitted, std.file.tempDir is used
///     prefix = prefix to give to the base name
///     ext = optional extension to append to the path (must contain '.')
/// Returns: a path (i.e. location/prefix-{uniquestring}.ext)
string tempPath(string location = null, string prefix = null, string ext = null)
in (!location || (exists(location) && isDir(location)))
in (!ext || ext.startsWith('.'))
out (res; (!location || res.startsWith(location)) && !exists(res))
{
    import std.array : array;
    import std.path : buildPath;
    import std.random : Random, unpredictableSeed, uniform;
    import std.range : generate, only, takeExactly;

    auto rnd = Random(unpredictableSeed);

    if (prefix)
        prefix ~= "-";

    if (!location)
        location = tempDir;

    string res;
    do
    {
        const basename = prefix ~ generate!(() => uniform!("[]")('a', 'z',
                rnd)).takeExactly(10).array ~ ext;

        res = buildPath(location, basename);
    }
    while (exists(res));

    return res;
}

@("hasDuplicates")
unittest
{
    assert(!hasDuplicates([1, 2, 3, 4, 5]));
    assert(!hasDuplicates([1, 5, 2, 4, 3]));
    assert(hasDuplicates([1, 2, 2, 3, 4, 5]));
    assert(hasDuplicates([1, 2, 3, 4, 1]));
}

void feedDigestData(D)(ref D digest, in string s) if (isDigest!D)
{
    digest.put(cast(const(ubyte)[]) s);
    digest.put(0);
}

void feedDigestData(D)(ref D digest, in string[] ss) if (isDigest!D)
{
    import std.bitmanip : nativeToLittleEndian;

    digest.put(nativeToLittleEndian(cast(uint) ss.length));
    foreach (s; ss)
    {
        digest.put(cast(const(ubyte)[]) s);
        digest.put(0);
    }
}

void feedDigestData(D, V)(ref D digest, in V val)
        if (isDigest!D && (isIntegral!V || is(V == enum)))
{
    import std.bitmanip : nativeToLittleEndian;

    digest.put(nativeToLittleEndian(cast(uint) val));
    digest.put(0);
}

/// Find a program executable name in the system PATH and return its full path
string findProgram(in string name)
{
    import std.process : environment;

    version (Windows)
    {
        import std.algorithm : endsWith;

        const efn = name.endsWith(".exe") ? name : name ~ ".exe";
    }
    else
    {
        const efn = name;
    }

    return searchInEnvPath(environment["PATH"], efn);
}

/// environment variable path separator
version (Posix)
    enum envPathSep = ':';
else version (Windows)
    enum envPathSep = ';';
else
    static assert(false);

/// Search for filename in the envPath variable content which can
/// contain multiple paths separated with sep depending on platform.
/// Returns: null if the file can't be found.
string searchInEnvPath(in string envPath, in string filename, in char sep = envPathSep)
{
    import std.algorithm : splitter;
    import std.file : exists;
    import std.path : buildPath;

    foreach (dir; splitter(envPath, sep))
    {
        const filePath = buildPath(dir, filename);
        if (exists(filePath))
            return filePath;
    }
    return null;
}

/// Search for filename pattern in the envPath variable content which can
/// contain multiple paths separated with sep depending on platform.
/// Returns: array of matching file names
string[] searchPatternInEnvPath(in string envPath, in string pattern, in char sep = envPathSep) @trusted
{
    import std.algorithm : map, splitter;
    import std.array : array;
    import std.file : dirEntries, exists, isDir, SpanMode;

    string[] res = [];

    foreach (dir; splitter(envPath, sep))
    {
        if (!exists(dir) || !isDir(dir))
            continue;
        res ~= dirEntries(dir, pattern, SpanMode.shallow).map!(de => de.name).array;
    }
    return res;
}

size_t indexOrLast(string s, char c) pure
{
    import std.string : indexOf;

    const ind = s.indexOf(c);
    return ind >= 0 ? ind : s.length;
}
