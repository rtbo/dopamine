module dopamine.log;

import arsd.terminal;

import std.format;
import std.stdio;

alias Color = arsd.terminal.Color;
alias Bright = arsd.terminal.Bright;

enum LogLevel
{
    verbose,
    info,
    warning,
    error,
    silent,
}

LogLevel minLogLevel = LogLevel.info;

auto color(Color color, const(char)[] text) @safe
{
    return ColorizedText(color, text);
}

auto info(const(char)[] text) @safe
{
    return ColorizedText(Color.DEFAULT | Bright, text);
}

auto success(const(char)[] text) @safe
{
    return ColorizedText(Color.green | Bright, text);
}

auto warning(const(char)[] text) @safe
{
    return ColorizedText(Color.yellow | Bright, text);
}

auto error(const(char)[] text) @safe
{
    return ColorizedText(Color.red | Bright, text);
}

void log(Args...)(LogLevel level, string msgf, Args args) @trusted
{
    if (level >= minLogLevel)
    {
        logging = true;
        scope (exit)
            logging = false;
        formattedWrite(instance, msgf, args);
        instance.put("\n");
        instance.flush();
    }
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

        logging = true;
        scope (exit)
            logging = false;

        size_t valI;
        auto f = fmt;

        while (f.length > 0)
        {
            if (f[0] == '%')
            {
                enforce(f.length > 1, "Invalid log format string: \"" ~ fmt ~ "\"");
                if (f[1] == '%')
                {
                    instance.put("%");
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
                instance.put(f[0 .. len]);
                f = f[len .. $];
            }
        }
        enforce(valI == values.length, "Orphean log format value");
        instance.put("\n");
        instance.flush();
    }
}

@("FormatLogException")
unittest
{
    auto oldInstance = instance;
    const oldLevel = minLogLevel;
    scope (exit)
    {
        instance = oldInstance;
        minLogLevel = oldLevel;
    }

    auto output = new TestLogOutput;
    instance = output;
    minLogLevel = LogLevel.info;

    auto e = new FormatLogException(LogLevel.info, "Test %s and %s. fourty-two = %s",
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

LogOutput instance;
bool logging; // true when currently logging through instance

static this()
{
    version (unittest)
    {
        // weird stuff happens with TerminalLogOutput
        // in multi threaded context generated by unit-threaded
        instance = new FlatLogOutput();
    }
    else
    {
        if (Terminal.stdoutIsTerminal())
        {
            instance = new TerminalLogOutput();
        }
        else
        {
            instance = new FlatLogOutput();
        }
    }
}

static ~this()
{
    // necessary to run Terminal.~this() out of GC collection
    destroy(instance);
    instance = null;
}

struct ColorizedText
{
    int color;
    const(char)[] text;

    void toString(scope void delegate(const(char)[]) sink)
    {
        if (logging)
        {
            instance.color(color);
            instance.put(text);
            instance.reset();
        }
        else
        {
            sink(text);
        }
    }
}

interface LogOutput
{
    void color(int col);
    void reset();
    void put(const(char)[] text);
    void flush();
}

class FlatLogOutput : LogOutput
{
    private File output;

    this()
    {
        output = stdout;
    }

    this(File output)
    {
        this.output = output;
    }

    override void color(int col)
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

class TerminalLogOutput : LogOutput
{
    private Terminal term;

    this()
    {
        term = Terminal(ConsoleOutputType.linear);
    }

    override void color(int col)
    {
        term.color(col, Color.DEFAULT);
    }

    override void reset()
    {
        term.reset();
    }

    override void put(const(char)[] msg)
    {
        term.write(msg);
    }

    override void flush()
    {
        term.flush();
    }
}

version (unittest)
{
    /// Testing output mock
    class TestLogOutput : LogOutput
    {
        import std.array : Appender;

        Appender!string output;

        override void color(int col)
        {
            import std.conv : to;

            auto c = cast(Color) col;
            output.put("[" ~ c.to!string ~ "]");
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
        formatValue(instance, value, spec);
    }
}
