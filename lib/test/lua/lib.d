module test.lua.lib;

import test.util;

import dopamine.lua.lib;
import dopamine.lua.util;

import bindbc.lua;
import std.string;

__gshared string testDirBase;
__gshared lua_State* utL; // state only for unit tests, not for recipe tests

shared static this()
{
    import std.path : dirName, buildNormalizedPath;
    import dopamine.lua : initLua;

    initLua();

    testDirBase = buildNormalizedPath(__FILE_FULL_PATH__.dirName.dirName);

    utL = luaL_newstate();

    luaL_openlibs(utL);
    luaLoadDopLib(utL);

    luaTestModule(utL);
    lua_setglobal(utL, "test");

    assert(lua_gettop(utL) == 0);
}

shared static ~this()
{
    lua_close(utL);
}

int luaTestPath(lua_State* L) nothrow
{
    import std.path : isAbsolute, dirSeparator;

    luaL_Buffer buf;
    luaL_buffinit(L, &buf);

    luaL_addlstring(&buf, &testDirBase[0], testDirBase.length);

    const n = lua_gettop(L);
    foreach (i; 1 .. n + 1)
    {
        luaL_addlstring(&buf, &dirSeparator[0], dirSeparator.length);

        size_t l;
        const s = luaL_checklstring(L, i, &l);
        if (i > 1 && isAbsolute(s[0 .. l]))
        {
            return luaL_argerror(L, i, "Invalid absolute path after first position");
        }
        if (!s)
            return 0;
        luaL_addlstring(&buf, s, l);
    }

    luaL_pushresult(&buf);
    return 1;
}

int luaTestAssertEq(lua_State* L) nothrow
{
    const narg = lua_gettop(L);

    if (narg <= 1)
        luaL_error(L, "assert_eq needs at least two param");

    for (int i = 2; i <= narg; i++)
    {
        if (!lua_rawequal(L, 1, i))
        {
            return L.catchAll!({
                const s1 = luaToString(L, 1);
                const s2 = luaToString(L, i);
                const msg = format("assertion failed: '%s' does not equal '%s'", s1, s2);
                return luaL_error(L, msg.toStringz);
            });
        }
    }
    return 0;
}

int luaTestAssertNEq(lua_State* L) nothrow
{
    const narg = lua_gettop(L);

    if (narg != 2)
        luaL_error(L, "assert_neq needs two param");

    if (lua_rawequal(L, 1, 2))
    {
        return L.catchAll!({
            const s1 = luaToString(L, 1);
            const s2 = luaToString(L, 2);
            const msg = format("assertion failed: '%s' equals '%s'", s1, s2);
            return luaL_error(L, msg.toStringz);
        });
    }
    return 0;
}

auto catchAll(alias fun)(lua_State* L) nothrow
{
    try
    {
        return fun();
    }
    catch (Exception ex)
    {
        luaL_error(L, ex.msg.toStringz);
    }
    assert(false);
}

int luaTestModule(lua_State* L) nothrow
{
    const funcs = [
        "path" : &luaTestPath, "assert_eq" : &luaTestAssertEq,
        "assert_neq" : &luaTestAssertNEq
    ];

    lua_createtable(L, 0, cast(int)(funcs.length));
    const libInd = lua_gettop(L);

    L.catchAll!({
        foreach (k, v; funcs)
        {
            lua_pushliteral(L, k);
            lua_pushcfunction(L, v);
            lua_settable(L, libInd);
        }
    });

    return 1;
}
