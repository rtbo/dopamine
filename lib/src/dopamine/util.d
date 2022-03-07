module dopamine.util;

import dopamine.log;

import std.digest;
import std.file;
import std.string;
import std.traits;
import std.typecons;

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

private struct LockFileImpl
{
    import std.stdio : File;

    private File f;
    private bool acq;

    bool opCast(T : bool)() const
    {
        return acq;
    }
}

/// Acquire a lock file.
/// The file is created if it doesn't exist.
/// If the file is locked by another process, the current thread
/// is blocked until the lock is released and acquired by this process.
/// The lock is released when the result goes out of scope.
auto acquireLockFile(string path) @trusted
{
    import std.algorithm : move;
    import std.stdio : File;

    auto f = File(path, "w");
    f.lock();
    return LockFileImpl(move(f), true);
}

/// Try to acquire a lock file.
/// The file is created if it doesn't exist.
/// If the file is locked by another process, the function returns immediately
/// and the result yields false in boolean context.
/// Otherwise a lock is acquired and the result yields true in boolean context.
/// The lock is released when the result goes out of scope.
auto tryAcquireLockFile(string path) @trusted
{
    import std.algorithm : move;
    import std.stdio : File;

    auto f = File(path, "w");
    const locked = f.tryLock();
    if (locked)
    {
        return LockFileImpl(move(f), true);
    }
    else
    {
        return LockFileImpl.init;
    }
}

struct JsonStateFile(T)
{
    import std.stdio : File;

    File f;

    this(string filename)
    {
        const mode = exists(filename) ? "r+b" : "w+b";
        f = File(filename, mode);
    }

    T read() @trusted
    {
        import vibe.data.json : deserializeJson;
        import std.exception : assumeUnique, enforce;

        const sz = f.size;

        if (sz == 0)
            return T.init;

        f.seek(0);

        auto bytes = new ubyte[sz];
        auto read = f.rawRead(bytes);

        enforce(read.length == bytes.length, "Could not read content of " ~ f.name);

        string json = cast(string) assumeUnique(read);
        return deserializeJson!T(json);
    }

    void write(const T val) @trusted
    {
        import vibe.data.json : serializeToJson, serializeToPrettyJson;

        f.seek(0);
        debug
        {
            serializeToPrettyJson(f.lockingTextWriter, val);
        }
        else
        {
            serializeToJson(f.lockingTextWriter, val);
        }

        version (Windows)
        {
            import core.sys.windows.winbase : SetEndOfFile;
            import std.windows.syserror : wenforce;

            wenforce(SetEndOfFile(f.windowsHandle), "Could not truncate " ~ f.name);
        }
        else version (Posix)
        {
            import core.sys.posix.unistd : ftruncate;
            import std.exception : errnoEnforce;

            errnoEnforce(!ftruncate(f.fileno, f.tell()), "Could not truncate " ~ f.name);
        }
    }
}

@("JsonStateFile")
unittest
{
    string deleteMe = tempPath(null, "statefile", ".json");
    scope (exit)
        remove(deleteMe);

    static struct TestStruct
    {
        string s;
        string[] ss;
    }

    alias TestStateFile = JsonStateFile!TestStruct;

    {
        auto tsf = TestStateFile(deleteMe);
        auto ts = tsf.read();
        static assert(is(typeof(ts) == TestStruct));
        assert(ts.s.length == 0);
        assert(ts.ss.length == 0);
        tsf.write(TestStruct("blah", ["foo", "bar", "baz"]));
    }
    {
        auto tsf = TestStateFile(deleteMe);
        auto ts = tsf.read();
        assert(ts.s == "blah");
        assert(ts.ss == ["foo", "bar", "baz"]);
        tsf.write(TestStruct("ç ç", ["é", "è"]));
    }
    {
        auto tsf = TestStateFile(deleteMe);
        auto ts = tsf.read();
        assert(ts.s == "ç ç");
        assert(ts.ss == ["é", "è"]);
    }
}

// /// Obtain an InputRange of `char` over the file
// auto fileChars(File file)
// {
//     return FileCharRange(file);
// }

// /// Obtain an InputRange of `dchar` over the file
// auto fileDChars(File file)
// {
//     return DCharRange(fileChars(file));
// }

// private struct FileCharRange
// {
//     private File f;
//     private char[4096] buf;
//     private char[] slc;
//     bool last;

//     this(File f)
//     {
//         this.f = f;
//         slc = this.f.rawRead(buf[]);
//         last = slc.length < buf.length;
//     }

//     @property bool empty()
//     {
//         return !slc.length;
//     }

//     @property char front()
//     {
//         return slc[0];
//     }

//     void popFront()
//     {
//         slc = slc[1 .. $];
//         if (!slc.length && !last)
//         {
//             slc = this.f.rawRead(buf[]);
//             last = slc.length < buf.length;
//         }
//     }
// }

// private struct DCharRange(R)
// if (isInputRange!R && is(ElementType!R == char))
// {
//     import std.utf : decodeFront;

//     private R chars;
//     private dchar c;

//     this(R chars)
//     {
//         this.chars = chars;
//         if (!this.chars.empty)
//             c = decodeFront(this.chars);
//     }

//     @property bool empty()
//     {
//         return chars.empty;
//     }

//     @property dchar front()
//     {
//         return c;
//     }

//     @property void popFront()
//     {
//         c = decodeFront(this.chars);
//     }
// }

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

struct SizeOfStr
{
    size_t bytes;
    double size;
    string unit;

    this(size_t bytes) pure @nogc
    {
        enum KiB = 1024;
        enum MiB = KiB * 1024;
        enum GiB = MiB * 1024;

        if (bytes >= GiB)
        {
            size = bytes / cast(double) GiB;
            unit = "GiB";
        }
        if (bytes >= MiB)
        {
            size = bytes / cast(double) MiB;
            unit = "MiB";
        }
        if (bytes >= KiB)
        {
            size = bytes / cast(double) KiB;
            unit = "KiB";
        }
        else
        {
            size = cast(double) bytes;
            unit = "B";
        }
    }

    string toString() const pure
    {
        import std.format : format;

        return format("%.1f %s", size, unit);
    }
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

/// Get all entries directly contained by dir
string[] allEntries(string dir) @trusted
{
    import std.algorithm : map;
    import std.array : array;
    import std.file : dirEntries, SpanMode;
    import std.path : asAbsolutePath, asRelativePath;

    dir = asAbsolutePath(dir).array;
    return dirEntries(dir, SpanMode.shallow, false).map!(d => d.name.asRelativePath(dir)
            .array).array;
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

/// Install a single file, that is copy it to dest unless dest exists and is not older.
/// Posix only: If preserveLinks is true and src is a symlink, dest is created as a symlink.
void installFile(const(char)[] src, const(char)[] dest, bool preserveLinks = true)
in (src.exists && src.isFile, src ~ " does not exist or is not a file")
{
    import std.path : dirName;
    import std.typecons : Yes;

    version (Posix)
    {
        const removeLink = dest.exists && dest.isSymlink;

        if (removeLink)
            remove(dest);

        if (preserveLinks && isSymlink(src))
        {
            const link = readLink(src);
            mkdirRecurse(dest.dirName);
            symlink(link, dest);

            logVerbose("%s %s -> %s", removeLink ? "Recreating symlink" : "Creating symlink  ",
                info(dest), color(Color.cyan, link));
            return;
        }
    }

    if (dest.exists && dest.timeLastModified >= src.timeLastModified)
    {
        logVerbose("Up-to-date         %s", info(dest));
        return;
    }

    logVerbose("Installing         %s", info(dest));

    mkdirRecurse(dest.dirName);
    copy(src, dest, Yes.preserveAttributes);
}

/// Recursively install from [src] to [dest].
/// If [src] is a file, do a single file install.
/// If [src] is a directory, do a recursive install.
/// If [preserveLinks] is true, links in [src] are reproduced in [dest]
/// If [preserveLinks] is false, a copy of the linked files in [src] are created in [dest]
/// [preserveLinks] has no effect on Windows (acts as preserveLinks==false)
void installRecurse(const(char)[] src, const(char)[] dest, bool preserveLinks = true) @system
{
    import std.exception : enforce;
    import std.path : buildNormalizedPath, buildPath, dirName;
    import std.string : startsWith;

    src = buildNormalizedPath(src);
    dest = buildNormalizedPath(dest);

    if (isDir(src))
    {
        mkdirRecurse(dest);

        auto entries = dirEntries(src.idup, SpanMode.breadth);
        foreach (entry; entries)
        {
            const dst = buildPath(dest, entry.name[src.length + 1 .. $]);
            // + 1 for the directory separator

            version (Posix)
            {
                if (preserveLinks && isSymlink(entry.name))
                {
                    const link = readLink(entry.name);
                    const fullPath = buildPath(dirName(entry.name), link).buildNormalizedPath();
                    enforce(fullPath.startsWith(src),
                        new FormatLogException("%s: %s links to %s which is outside of %s",
                            error("Error"), entry.name, fullPath, src));
                }
            }

            if (isFile(entry.name))
                installFile(entry.name, dst, preserveLinks);
            else
                mkdirRecurse(dst);
        }
    }
    else
        installFile(src, dest, preserveLinks);
}

@("installRecurse")
@system unittest
{
    import std.path : buildPath;

    const src = tempPath();
    mkdirRecurse(src);
    const dest = tempPath();

    scope (exit)
    {
        rmdirRecurse(src);
        rmdirRecurse(dest);
    }

    // building tree:
    //  - file1.txt
    //  - file2.txt
    //  - file3.txt
    //  - subdir/file4.txt
    //  - link1.txt -> file1.txt
    //  - link2.txt -> link1.txt
    //  - link3.txt -> subdir/file4.txt
    //  - subdir/link4.txt -> file4.txt
    //  - subdir/link5.txt -> link4.txt
    // (symlinks only created and tested on Posix)
    mkdir(buildPath(src, "subdir"));
    write(buildPath(src, "file1.txt"), "file1");
    write(buildPath(src, "file2.txt"), "file2");
    write(buildPath(src, "file3.txt"), "file3");
    write(buildPath(src, "subdir", "file4.txt"), "file4");

    version (Posix)
    {
        symlink("file1.txt", buildPath(src, "link1.txt"));
        symlink("link1.txt", buildPath(src, "link2.txt"));
        symlink("subdir/file4.txt", buildPath(src, "link3.txt"));
        symlink("file4.txt", buildPath(src, "subdir", "link4.txt"));
        symlink("link4.txt", buildPath(src, "subdir", "link5.txt"));
    }

    installRecurse(src, dest);

    assert(read(buildPath(dest, "file1.txt")) == "file1");
    assert(read(buildPath(dest, "file2.txt")) == "file2");
    assert(read(buildPath(dest, "file3.txt")) == "file3");
    assert(read(buildPath(dest, "subdir", "file4.txt")) == "file4");

    version (Posix)
    {
        assert(read(buildPath(dest, "link1.txt")) == "file1");
        assert(read(buildPath(dest, "link2.txt")) == "file1");
        assert(read(buildPath(dest, "link3.txt")) == "file4");
        assert(read(buildPath(dest, "subdir", "link4.txt")) == "file4");
        assert(read(buildPath(dest, "subdir", "link5.txt")) == "file4");

        assert(readLink(buildPath(dest, "link1.txt")) == "file1.txt");
        assert(readLink(buildPath(dest, "link2.txt")) == "link1.txt");
        assert(readLink(buildPath(dest, "link3.txt")) == "subdir/file4.txt");
        assert(readLink(buildPath(dest, "subdir", "link4.txt")) == "file4.txt");
        assert(readLink(buildPath(dest, "subdir", "link5.txt")) == "link4.txt");
    }
}

void runCommand(in string[] cmd, string workDir = null,
    LogLevel logLevel = LogLevel.verbose, string[string] env = null) @trusted
{
    import std.algorithm : canFind;
    import std.conv : to;
    import std.exception : assumeUnique, enforce;
    import std.process : Config, escapeShellCommand, Pid, spawnProcess, wait;
    import std.stdio : stdin, stdout, stderr, File;

    version (Windows)
        enum nullFile = "NUL";
    else version (Posix)
        enum nullFile = "/dev/null";
    else
        static assert(0);

    auto childStdout = stdout;
    auto childStderr = stderr;
    auto config = Config.retainStdout | Config.retainStderr;
    string outLog;
    string errLog;

    // TODO buffer stdout and stderr to populate e.g. CommandFailedException

    if (minLogLevel > logLevel)
    {
        outLog = tempPath(null, "stdout", ".txt");
        errLog = tempPath(null, "stderr", ".txt");
        childStdout = File(outLog, "w");
        childStderr = File(errLog, "w");
    }

    if (workDir)
    {
        log(logLevel, "Running from %s", info(workDir));
    }

    const tplt = cmd[0].canFind(' ') ? `"%s" %s` : "%s %s";

    log(logLevel, tplt, info(cmd[0]), cmd[1 .. $].commandRep);
    auto pid = spawnProcess(cmd, stdin, childStdout, childStderr, env, config, workDir);
    const status = pid.wait();

    if (status != 0)
    {
        import std.file : read;
        import std.format : format;

        string outMsg;
        string errMsg;
        if (outLog)
        {
            const content = cast(const(char)[]) read(outLog);
            outMsg = assumeUnique("\n----- command stdout -----\n" ~ content);
        }
        if (errLog)
        {
            const content = cast(const(char)[]) read(errLog);
            errMsg = assumeUnique("\n----- command stderr -----\n" ~ content);
        }

        throw new FormatLogException("%s: %s failed with code %s\n%s%s%s",
            error("Error"), info(cmd[0]), status, cmd.commandRep, outMsg, errMsg);
    }
}

@property string commandRep(in string[] cmd)
{
    import std.algorithm : canFind, map;
    import std.array : join;

    return cmd.map!(c => c.canFind(' ') ? '"' ~ c ~ '"' : c).join(" ");
}
