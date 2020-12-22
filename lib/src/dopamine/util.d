module dopamine.util;

import dopamine.log;

import std.digest;
import std.traits;

@safe:

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

/// An file written to flag that a condition is met
struct FlagFile
{
    string path;

    @property bool exists()
    {
        import std.file : exists;

        return exists(path);
    }

    string read() @trusted
    in(exists)
    {
        import std.exception : assumeUnique;
        import std.file : read;

        return cast(string) assumeUnique(read(path));
    }

    void write(string content = "")
    {
        import std.file : mkdirRecurse, write;
        import std.path : dirName;

        mkdirRecurse(dirName(path));
        write(path, content);
    }

    void remove()
    {
        import std.file : exists, remove;

        if (exists(path))
            remove(path);
    }

    @property auto timeLastModified()
    {
        import std.file : timeLastModified;

        return timeLastModified(path);
    }
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

void runCommand(in string[] command, string workDir = null,
        LogLevel logLevel = LogLevel.verbose, string[string] env = null) @trusted
{
    runCommands((&command)[0 .. 1], workDir, logLevel, env);
}

void runCommands(in string[][] commands, string workDir = null,
        LogLevel logLevel = LogLevel.verbose, string[string] env = null) @trusted
{
    import std.conv : to;
    import std.exception : enforce;
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

    // TODO buffer stdout and stderr to populate e.g. CommandFailedException

    if (minLogLevel > logLevel)
    {
        childStdout = File(nullFile, "w");
        childStderr = File(nullFile, "w");
    }

    if (workDir)
    {
        log(logLevel, "Running from %s", info(workDir));
    }

    foreach (cmd; commands)
    {
        log(logLevel, cmd.commandRep);
        auto pid = spawnProcess(cmd, stdin, childStdout, childStderr, env, config, workDir);
        auto exitcode = pid.wait();
        enforce(exitcode == 0,
                "Command failed with exit code " ~ to!string(exitcode) ~ ": " ~ cmd.commandRep);
    }
}

@property string commandRep(in string[] cmd)
{
    import std.array : join;

    return cmd.join(" ");
}

struct SizeOfStr
{
    size_t bytes;
    double size;
    string unit;

    string toString() const
    {
        import std.format : format;

        return format("%.1f %s", size, unit);
    }
}

SizeOfStr convertBytesSizeOf(in size_t bytes) pure @nogc nothrow
{
    enum KiB = 1024;
    enum MiB = KiB * 1024;
    enum GiB = MiB * 1024;

    if (bytes >= GiB)
    {
        return SizeOfStr(bytes, bytes / cast(double) GiB, "GiB");
    }
    if (bytes >= MiB)
    {
        return SizeOfStr(bytes, bytes / cast(double) MiB, "MiB");
    }
    if (bytes >= KiB)
    {
        return SizeOfStr(bytes, bytes / cast(double) KiB, "KiB");
    }
    return SizeOfStr(bytes, cast(double) bytes, "B");
}
