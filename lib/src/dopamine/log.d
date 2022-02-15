/// A logging module that support colorized text when connected to a terminal.
module dopamine.log;

import std.format;
import std.stdio;

enum Color
{
    black = 0,

    red = RED_BIT,
    green = GREEN_BIT,
    blue = BLUE_BIT,

    yellow = red | green,
    magenta = red | blue,
    cyan = blue | green,

    white = red | green | blue,

    bright = BRIGHT_BIT,
}

enum LogLevel
{
    /// Log level that is typically activated with a --verbose switch
    verbose,
    /// Regular information log level
    info,
    /// Warning log level, that will print on stderr
    warning,
    /// Error log level, that will print on stderr
    error,
    /// If [minLogLevel] is set to [silent], nothing will be printed, not even errors
    silent,
}


/// Filters what level of logging actually goes to output.
@property LogLevel minLogLevel()
{
    return _minLogLevel;
}
/// ditto
@property void minLogLevel(LogLevel level)
{
    _minLogLevel = level;
}

/// Set the output for the specified level
/// By default, logging defaults to stdout, except for levels starting from [LogLevel.warning].
void setLogOutput(LogLevel level, File output)
in (level < LogLevel.silent)
{
    const ind = cast(size_t)level;
    if (logOutputs[ind])
    {
        logOutputs[ind].dispose();
    }
    logOutputs[ind] = LogOutput.makeFor(output);
}

/// Whether [logDebug] output is activated.
/// This is separated from other levels because we don't necessarily need verbose with debug,
/// and we certainly don't want debug with verbose (one is for development, the other part of UI)
bool debugEnabled = false;

/// Set the file where the debug output is logged
/// By default it is stdout
void setDebugOutput(File output)
{
    if (debugOutput)
        debugOutput.dispose();
    debugOutput = LogOutput.makeFor(output);
}

auto color(Color color, const(char)[] text) @safe
{
    return ColorizedText(color, text);
}

auto info(const(char)[] text) @safe
{
    return ColorizedText(Color.white | Color.bright, text);
}

auto success(const(char)[] text) @safe
{
    return ColorizedText(Color.green | Color.bright, text);
}

auto warning(const(char)[] text) @safe
{
    return ColorizedText(Color.yellow | Color.bright, text);
}

auto error(const(char)[] text) @safe
{
    return ColorizedText(Color.red | Color.bright, text);
}

private void privLog(Args...)(LogLevel level, string msgf, Args args) @trusted
{
    if (level >= _minLogLevel)
    {
        auto output = logOutput(level);
        assert(output);
        doLog(output, msgf, args);
    }
}

void log(Args...)(LogLevel level, string msgf, Args args) @trusted
{
    import std.exception : enforce;

    enforce(level < LogLevel.silent, "Can't log to silent log level!");

    privLog(level, msgf, args);
}

void logDebug(Args...)(string msgf, Args args) @safe
{
    if (debugEnabled)
    {
        doLog(debugOutput, msgf, args);
    }
}

void logVerbose(Args...)(string msgf, Args args) @safe
{
    privLog(LogLevel.warning, msgf, args);
}

void logInfo(Args...)(string msgf, Args args) @safe
{
    privLog(LogLevel.warning, msgf, args);
}

void logWarning(Args...)(string msgf, Args args) @safe
{
    privLog(LogLevel.warning, msgf, args);
}

void logError(Args...)(string msgf, Args args) @safe
{
    privLog(LogLevel.error, msgf, args);
}

/// Exception that formats its argument according a format string
/// and that can also log itself to the [log] API.
class FormatLogException : Exception
{
    LogLevel level = LogLevel.error;
    string fmt;
    Object[] values;

    this(Args...)(string fmt, Args args)
    {
        super(format(fmt, args));
        this.fmt = fmt;
        static foreach (arg; args)
        {
            values ~= new TDynLogValue!(typeof(arg))(arg);
        }
    }

    this(Args...)(LogLevel level, string fmt, Args args)
    {
        super(format(fmt, args));
        this.level = level;
        this.fmt = fmt;
        static foreach (arg; args)
        {
            values ~= new TDynLogValue!(typeof(arg))(arg);
        }
    }

    void log()
    {
        import std.exception : enforce;

        if (level < _minLogLevel)
            return;

        logging = logOutput(level);

        scope (exit)
            logging = null;

        size_t valI;
        auto f = fmt;

        while (f.length > 0)
        {
            if (f[0] == '%')
            {
                enforce(f.length > 1, "Invalid log format string: \"" ~ fmt ~ "\"");
                if (f[1] == '%')
                {
                    logging.put("%");
                    f = f[2 .. $];
                    continue;
                }
                size_t len = 1;
                while (!isEndOfSpec(f[len]))
                {
                    ++len;
                    enforce(f.length > len, "Invalid log format string: \"" ~ fmt ~ "\"");
                }
                enforce(valI < values.length, "Orphean log format specifier");
                auto val = cast(DynLogValue) values[valI];
                const spec = singleSpec(f[0 .. len + 1]);
                val.formatVal(spec);
                f = f[len + 1 .. $];
                valI++;
            }
            else
            {
                size_t len = 1;
                while (f.length > len && f[len] != '%')
                    len++;
                logging.put(f[0 .. len]);
                f = f[len .. $];
            }
        }
        enforce(valI == values.length, "Orphean log format value");
        logging.put("\n");
        logging.flush();
    }
}

@("FormatLogException")
unittest
{
    auto oldOutput = logOutputs[0];
    const oldLevel = minLogLevel;
    scope (exit)
    {
        logOutputs[0] = oldOutput;
        minLogLevel = oldLevel;
    }

    auto output = new TestLogOutput;
    logOutputs[0] = output;
    minLogLevel = LogLevel.verbose;

    auto e = new FormatLogException(LogLevel.verbose, "Test %s and %s. fourty-two = %s",
        ColorizedText(Color.green, "success"), ColorizedText(Color.red, "error"), 42);

    enum expectedMsg = "Test success and error. fourty-two = 42";
    enum expectedLog = "Test [green]success[reset] and [red]error[reset]. fourty-two = 42\n[flush]";

    assert(e.message == expectedMsg);
    assert(output.output.data == "");

    e.log();

    assert(e.message == expectedMsg);
    assert(output.output.data == expectedLog);
}

private:

version (Windows)
{
    import core.sys.windows.windows;

    void winEnforce(BOOL res, string fname)
    {
        if (!res)
        {
            // from https://stackoverflow.com/a/17387176/1382702

            const errorMessageId = GetLastError();
            if (!errorMessageId)
            {
                throw new Exception(format("%s failed, (but GetLastError do not report error)", fname));
            }

            LPSTR messageBuffer = null;

            // Ask Win32 to give us the string version of that message ID.
            // The parameters we pass in, tell Win32 to create the buffer that holds the message for us 
            // (because we don't yet know how long the message string will be).
            const size = FormatMessageA(
                FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                null, 
                errorMessageId,
                MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                messageBuffer, 
                0,
                null
            );

            //Copy the error message into a string.
            const msg = messageBuffer[0 .. size].idup;

            //Free the Win32's string's buffer.
            LocalFree(messageBuffer);

            throw new Exception(format("%s failed (%s)", fname, msg));
        }
    }
}

bool isConsole(File file)
{
    version (Windows)
    {
        return GetFileType(file.windowsHandle) == FILE_TYPE_CHAR;
    }
    version (Posix)
    {
        import core.sys.posix.unistd : isatty;

        return cast(bool) isatty(file.fileno);
    }
}

version (Windows)
{
    enum RED_BIT = FOREGROUND_RED;
    enum GREEN_BIT = FOREGROUND_GREEN;
    enum BLUE_BIT = FOREGROUND_BLUE;
    enum BRIGHT_BIT = FOREGROUND_INTENSITY;
}
version (Posix)
{
    enum RED_BIT = 1;
    enum GREEN_BIT = 2;
    enum BLUE_BIT = 4;
    enum BRIGHT_BIT = 8;
}

bool isEndOfSpec(char c)
{
    switch (c)
    {
    case 's':
    case 'c':
    case 'b':
    case 'd':
    case 'o':
    case 'x':
    case 'X':
    case 'e':
    case 'E':
    case 'f':
    case 'F':
    case 'g':
    case 'G':
    case 'a':
    case 'A':
        return true;
    default:
        return false;
    }
}

LogLevel _minLogLevel = LogLevel.info;

enum levelCount = cast(size_t)LogLevel.silent;

LogOutput[levelCount] logOutputs;

LogOutput debugOutput;

// set when currently logging because ColorizedText 
// need a reference to the currently logging output.
LogOutput logging;

LogOutput logOutput(LogLevel level)
    in(level < LogLevel.silent)
{
    const ind = cast(size_t)level;
    return logOutputs[ind];
}


static this()
{
    // we could reuse the same stdout and stderr instances, but it would cause
    // problem to release the handle (we assign to File.init in dispose)
    // in case some file system file is set.
    logOutputs[cast(size_t)LogLevel.verbose] = LogOutput.makeFor(stdout);
    logOutputs[cast(size_t)LogLevel.info] = LogOutput.makeFor(stdout);
    logOutputs[cast(size_t)LogLevel.warning] = LogOutput.makeFor(stderr);
    logOutputs[cast(size_t)LogLevel.error] = LogOutput.makeFor(stderr);
    debugOutput = LogOutput.makeFor(stdout);
}

static ~this()
{
    logOutputs[cast(size_t)LogLevel.verbose].dispose();
    logOutputs[cast(size_t)LogLevel.info].dispose();
    logOutputs[cast(size_t)LogLevel.warning].dispose();
    logOutputs[cast(size_t)LogLevel.error].dispose();
    debugOutput.dispose();
}

void doLog(Args...)(LogOutput output, string msgf, Args args)
{
    logging = output;
    scope (exit)
    {
        logging = null;
    }

    formattedWrite(logging, msgf, args);
    logging.put("\n");
    logging.flush();
}

struct ColorizedText
{
    Color color;
    const(char)[] text;

    void toString(scope void delegate(const(char)[]) sink) const
    {
        if (logging)
        {
            logging.color(color);
            logging.put(text);
            logging.reset();
        }
        else
        {
            sink(text);
        }
    }
}

interface LogOutput
{
    void color(Color col);
    void reset();
    void put(const(char)[] text);
    void flush();
    void dispose();

    static LogOutput makeFor(File file)
    {
        if (isConsole(file))
        {
            return new TerminalLogOutput(file);
        }
        else
        {
            return new FlatLogOutput(file);
        }
    }
}

class FlatLogOutput : LogOutput
{
    private File output;

    this(File output)
    {
        this.output = output;
    }

    override void color(Color col)
    {
    }

    override void reset()
    {
    }

    override void put(const(char)[] msg)
    {
        output.write(msg);
    }

    override void flush()
    {
        output.flush();
    }

    override void dispose()
    {
        output = File.init;
    }
}

enum defaultForeground = Color.white;

class TerminalLogOutput : LogOutput
{
    File output;
    version (Windows)
    {
        WORD resetAttribute;
    }

    this(File output)
    {
        this.output = output;
        version (Windows)
        {
            CONSOLE_SCREEN_BUFFER_INFO info;
            winEnforce(
                GetConsoleScreenBufferInfo(output.windowsHandle, &info),
                "GetConsoleScreenBufferInfo"
            );
            resetAttribute = info.wAttributes;
        }
    }

    override void color(Color col)
    {
        version (Windows)
        {
            SetConsoleTextAttribute(output.windowsHandle, cast(WORD) col);
        }
        version (Posix)
        {
            const tint = col & ~Color.bright;
            const bright = col & Color.bright;
            output.rawWrite(format("\u001B[3%d%sm", cast(int) tint, bright ? ";1" : ""));
        }
    }

    override void reset()
    {
        version (Windows)
        {
            SetConsoleTextAttribute(output.windowsHandle, resetAttribute);
        }

        version (Posix)
        {
            output.rawWrite("\u001B[0m");
        }
    }

    override void put(const(char)[] msg)
    {
        output.write(msg);
    }

    override void flush()
    {
        output.flush();
    }

    override void dispose()
    {
        output = File.init;
    }
}

version (unittest)
{
    /// Testing output mock
    class TestLogOutput : LogOutput
    {
        import std.array : Appender;

        Appender!string output;

        override void color(Color col)
        {
            import std.conv : to;

            output.put("[" ~ col.to!string ~ "]");
        }

        override void reset()
        {
            output.put("[reset]");
        }

        override void put(const(char)[] msg)
        {
            output.put(msg);
        }

        override void flush()
        {
            output.put("[flush]");
        }

        override void dispose()
        {
        }
    }
}

abstract class DynLogValue
{
    abstract void formatVal(scope const ref FormatSpec!char spec);
}

class TDynLogValue(T) : DynLogValue
{
    T value;

    this(T value)
    {
        this.value = value;
    }

    override void formatVal(scope const ref FormatSpec!char spec)
    {
        formatValue(logging, value, spec);
    }
}
