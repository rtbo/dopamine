module dopamine.lua.profile;

import dopamine.lua.util;
import dopamine.profile;
import bindbc.lua;

package(dopamine):

/// Push on the stack a table with the data of profile
void luaPushProfile(lua_State* L, const(Profile) profile)
{
    lua_newtable(L);
    const ind = lua_gettop(L);

    luaSetTable(L, ind, "basename", profile.basename);
    luaSetTable(L, ind, "name", profile.name);

    lua_pushliteral(L, "host");
    lua_createtable(L, 0, 2);
    const hostInd = lua_gettop(L);
    luaSetTable(L, hostInd, "os", profile.hostInfo.os.toConfig);
    luaSetTable(L, hostInd, "arch", profile.hostInfo.arch.toConfig);
    lua_settable(L, ind); // host table

    luaSetTable(L, ind, "build_type", profile.buildType.toConfig);

    lua_pushliteral(L, "compilers");
    lua_createtable(L, 0, cast(int) profile.compilers.length);
    const compsInd = lua_gettop(L);
    foreach (const ref comp; profile.compilers)
    {
        const lang = comp.lang.toConfig();
        lua_pushlstring(L, lang.ptr, lang.length);

        lua_createtable(L, 0, 3);
        const compInd = lua_gettop(L);
        luaSetTable(L, compInd, "name", comp.name);
        luaSetTable(L, compInd, "version", comp.ver);
        luaSetTable(L, compInd, "path", comp.path);

        lua_settable(L, compsInd);
    }
    lua_settable(L, ind); // compilers table

    luaSetTable(L, ind, "digest_hash", profile.digestHash);
}

/// Read a profile from a lua table at index ind
const(Profile) luaReadProfile(lua_State* L, int ind)
{
    import std.exception : enforce;

    ind = positiveStackIndex(L, ind);

    const basename = luaGetTable!string(L, ind, "basename");

    lua_getfield(L, ind, "host");
    enforce(lua_type(L, -1) == LUA_TTABLE, "Cannot find host profile table");
    const arch = fromConfig!Arch(luaGetTable!string(L, -1, "arch"));
    const os = fromConfig!OS(luaGetTable!string(L, -1, "os"));
    lua_pop(L, 1);
    const host = HostInfo(arch, os);

    const buildType = fromConfig!BuildType(luaGetTable!string(L, ind, "build_type"));

    lua_getfield(L, ind, "compilers");
    const compInd = lua_gettop(L);
    enforce(lua_type(L, -1) == LUA_TTABLE, "Cannot find compilers profile table");
    Compiler[] compilers;
    lua_pushnil(L);
    while (lua_next(L, compInd) != 0)
    {
        enforce(lua_type(L, -2) == LUA_TSTRING, "Compilers table key must be language name");

        const lang = fromConfig!Lang(luaTo!string(L, -2));

        // compiler table at index -1
        const name = luaGetTable!string(L, -1, "name");
        const ver = luaGetTable!string(L, -1, "version");
        const path = luaGetTable!string(L, -1, "path");

        compilers ~= Compiler(lang, name, ver, path);

        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    const hash = luaGetTable!string(L, ind, "digest_hash");

    auto profile = new Profile(basename, host, buildType, compilers);

    enforce(hash == profile.digestHash,
            "Error: hash mismatch between profile rebuilt from Lua and original");

    return profile;
}

@("Profile can pass to lua and come back identical")
unittest
{
    import test.util : ensureDefaultProfile;

    auto L = luaL_newstate();
    scope (exit)
        lua_close(L);

    auto profile = ensureDefaultProfile();
    luaPushProfile(L, profile);
    auto copy = luaReadProfile(L, -1);

    assert(profile.name == copy.name);
    assert(profile.digestHash == copy.digestHash);
}
