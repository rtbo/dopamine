module test.main;

import test.util : testPath;

import unit_threaded;

import std.exception : enforce;
import std.process : execute;

shared static this()
{
    import dopamine.log : minLogLevel, LogLevel;
    import dopamine.lua : initLua;

    initLua();

    minLogLevel = LogLevel.verbose;

    enforce(execute(["dub", "add-path", testPath("data")]).status == 0);
}

shared static ~this()
{
    enforce(execute(["dub", "remove-path", testPath("data")]).status == 0);
}

mixin runTestsMain!("dopamine.api.transport", "dopamine.depdag",
        "dopamine.dependency", "dopamine.deplock", "dopamine.log",
        "dopamine.login", "dopamine.lua.lib", "dopamine.lua.profile",
        "dopamine.semver", "dopamine.util", "test.recipe",);
