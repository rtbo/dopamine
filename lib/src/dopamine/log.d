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
    /// Log level only for debugging.
    /// Debug output is enabled with [debugEnabled], [minLogLevel] does not interfere with it.
    /// That way [logDebug] can be used without [logVerbose] pollution and vice-versa.
    debug_,
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

LogLevel minLogLevel = LogLevel.info;
bool debugEnabled = false;

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

void log(Args...)(LogLevel level, string msgf, Args args) @trusted
{
    if (level == LogLevel.debug_ && debugEnabled)
    {
        doLog(stdoutOutput, msgf, args);
    }
    else if (level != level.debug_ && level >= minLogLevel)
    {
        auto output = level >= LogLevel.warning ? stderrOutput : stdoutOutput;
        doLog(output, msgf, args);
    }
}

void logDebug(Args...)(string msgf, Args args) @safe
{
    log(LogLevel.debug_, msgf, args);
}

void logVerbose(Args...)(string msgf, Args args) @safe
{
    log(LogLevel.verbose, msgf, args);
}

void logInfo(Args...)(string msgf, Args args) @safe
{
    log(LogLevel.info, msgf, args);
}

void logWarning(Args...)(string msgf, Args args) @safe
{
    log(LogLevel.warning, msgf, args);
}

void logError(Args...)(string msgf, Args args) @safe
{
    log(LogLevel.error, msgf, args);
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

        if (level < minLogLevel)
            return;

        logging = level >= LogLevel.warning ? stderrOutput : stdoutOutput;
        scope (exit)
        {
            logging = null;
        }

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
    auto oldOutput = stderrOutput;
    const oldLevel = minLogLevel;
    scope (exit)
    {
        stderrOutput = oldOutput;
        minLogLevel = oldLevel;
    }

    auto output = new TestLogOutput;
    stderrOutput = output;
    minLogLevel = LogLevel.info;

    auto e = new FormatLogException(LogLevel.warning, "Test %s and %s. fourty-two = %s",
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

            LPSTR messageBuffer = nullptr;

            //Ask Win32 to give us the string version of that message ID.
            //The parameters we pass in, tell Win32 to create the buffer that holds the message for us (because we don't yet know how long the message string will be).
            size_t size = FormatMessageA(
                FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                NULL, errorMessageID, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), (LPSTR) & messageBuffer, 0, NULL);

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

LogOutput stdoutOutput;
LogOutput stderrOutput;
// set when currently logging because ColorizedText has no reference to it
LogOutput logging;

static this()
{
    stdoutOutput = LogOutput.makeFor(stdout);
    stderrOutput = LogOutput.makeFor(stderr);
}

static ~this()
{
    stdoutOutput = null;
    stderrOutput = null;
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
            winEnforce(GetConsoleScreenBufferInfo(output.windowsHandle, &info));
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
