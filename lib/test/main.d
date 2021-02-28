module test.main;

import test.util : testPath;


import dopamine.api.transport;
import dopamine.depdag;
import dopamine.dependency;
import dopamine.deplock;
import dopamine.log;
import dopamine.login;
import dopamine.lua.lib;
import dopamine.lua.profile;
import dopamine.paths;
import dopamine.profile;
import dopamine.semver;
import dopamine.util;
import test.recipe;

import std.exception : enforce;
import std.process : execute;
import std.meta;


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

int main()
{
    return 0;
}

alias allModules = AliasSeq!(
    dopamine.api.transport,
    dopamine.depdag,
    dopamine.dependency,
    dopamine.deplock,
    dopamine.log,
    dopamine.login,
    dopamine.lua.lib,
    dopamine.lua.profile,
    dopamine.paths,
    dopamine.profile,
    dopamine.semver,
    dopamine.util,
    test.recipe,
);
