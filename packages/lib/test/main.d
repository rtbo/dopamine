module test.main;

import test.util : testPath;

import std.exception : enforce;
import std.process : execute;

shared static this()
{
    import dopamine.log : minLogLevel, LogLevel;

    minLogLevel = LogLevel.error;

    enforce(execute(["dub", "add-path", testPath("pkgs")]).status == 0);
}

shared static ~this()
{
    enforce(execute(["dub", "remove-path", testPath("pkgs")]).status == 0);
}
