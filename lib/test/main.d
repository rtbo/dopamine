module test.main;

import unit_threaded;

shared static this()
{
    import dopamine.log : minLogLevel, LogLevel;
    import dopamine.lua : initLua;
    import test.util : testPath;
    import std.file : exists, rmdirRecurse;

    initLua();

    minLogLevel = LogLevel.verbose;

    const genPath = testPath("gen");
    if (exists(genPath))
        rmdirRecurse(genPath);
}

mixin runTestsMain!(
    "dopamine.api.transport",
    "dopamine.depdag",
    "dopamine.dependency",
    "dopamine.deplock",
    "dopamine.log",
    "dopamine.login",
    "dopamine.lua.lib",
    "dopamine.lua.profile",
    "dopamine.semver",
    "dopamine.util",
    "test.recipe",
);
