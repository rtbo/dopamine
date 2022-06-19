module dopamine.server.utils;

import vibe.http.server;

import std.format;

class StatusException : Exception
{
    int statusCode;
    string reason;

    this(int statusCode, string reason = null, string file = __FILE__, size_t line = __LINE__) @safe
    {
        super(format!"%s: %s%s"(statusCode, httpStatusText(statusCode), reason ? "\n" ~ reason : ""), file, line);
        this.statusCode = statusCode;
        this.reason = reason;
    }
}

T enforceStatus(T)(T condition, int statusCode, string reason = null,
    string file = __FILE__, size_t line = __LINE__) @safe
{
    static assert(is(typeof(!condition)), "condition must cast to bool");
    if (!condition)
        throw new StatusException(statusCode, reason, file, line);
    return condition;
}

noreturn statusError(int statusCode, string reason = null, string file = __FILE__, size_t line = __LINE__) @safe
{
    throw new StatusException(statusCode, reason, file, line);
}

enum currentApiLevel = 1;
