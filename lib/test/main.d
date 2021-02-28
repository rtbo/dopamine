module test.main;

import test.util : testPath;

import std.exception : enforce;
import std.process : execute;


shared static this()
{
    import dopamine.log : minLogLevel, LogLevel;
    import dopamine.lua : initLua;

    initLua();

    minLogLevel = LogLevel.silent;

    enforce(execute(["dub", "add-path", testPath("data")]).status == 0);
}

shared static ~this()
{
    enforce(execute(["dub", "remove-path", testPath("data")]).status == 0);
}

int main()
{
    return 0;
}
