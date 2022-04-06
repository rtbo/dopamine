module test.lua.ut;

import test.lua.lib;
import test.util;

import dopamine.lua.util;
import dopamine.util;

import bindbc.lua;

import std.file;
import std.path;
import std.string;

/// test assertions in the given lua string
void testLuaStr(lua_State* L, string lua)
{
    const res = luaL_dostring(L, lua.toStringz);

    string err;
    if (res != LUA_OK)
    {
        err = luaPop!string(L);
    }
    assert(res == LUA_OK, err);
    assert(lua_gettop(L) == 0, "test did not clean lua stack");
}

@("lua.testscripts")
unittest
{
    import std.algorithm : filter;

    auto L = makeTestL();
    scope (exit)
        lua_close(L);

    testPath("lua").fromDir!({
        foreach (e; dirEntries(testPath("lua"), SpanMode.breadth).filter!(
            e => e.name.endsWith(".lua")))
        {
            const fn = e.name.baseName;
            const res = luaL_dofile(L, e.name.toStringz);
            string err;
            if (res != LUA_OK)
            {
                err = luaPop!string(L);
            }
            assert(res == LUA_OK, err);
            assert(lua_gettop(L) == 0, "test " ~ fn ~ " did not clean lua stack");
        }
    });
}

@("lua.run_cmd")
unittest
{
    import std.path : dirName;
    import std.string : replace;

    auto L = makeTestL();
    scope (exit)
        lua_close(L);

    const thisDir = dirName(__FILE_FULL_PATH__).replace('\\', '/');

    version (Windows)
    {
        const lsCmd = "dir .";
    }
    else
    {
        const lsCmd = "ls .";
    }

    const lua = format(`
        local ls_res = dop.from_dir('%s', function()
            return dop.run_cmd({
                '%s',
                catch_output=true,
                shell=true,
            })
        end)

        assert(string.find(ls_res, 'lib.d'))
        assert(string.find(ls_res, 'ut.d'))
        assert(string.find(ls_res, 'dir_name.lua'))
        assert(string.find(ls_res, 'pkgconfig.lua'))
    `, thisDir, lsCmd);

    testLuaStr(L, lua);
}
