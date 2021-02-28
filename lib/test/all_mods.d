// Hard coding allModules waiting for meson#8435
module test.all_mods;

import std.meta : AliasSeq;

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
