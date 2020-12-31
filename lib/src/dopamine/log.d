module dopamine.log;

import arsd.terminal;

import std.format;
import std.stdio;

enum LogLevel
{
    verbose,
    info,
    warning,
    error,
    silent,
}

LogLevel minLogLevel = LogLevel.info;

auto color(Color color, string text) @safe
{
    return ColorizedText(color, text);
}

auto info(string text) @safe
{
    return ColorizedText(Color.DEFAULT | Bright, text);
}

auto success(string text) @safe
{
    return ColorizedText(Color.green | Bright, text);
}

auto warning(string text) @safe
{
    return ColorizedText(Color.yellow | Bright, text);
}

auto error(string text) @safe
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

private:

LogOutput instance;
bool logging; // true when currently logging through instance

static this()
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

static ~this()
{
    // necessary to run Terminal.~this() out of GC collection
    destroy(instance);
    instance = null;
}

struct ColorizedText
{
    int color;
    string text;

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
