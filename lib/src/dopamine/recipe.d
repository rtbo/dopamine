module dopamine.recipe;

import dopamine.build;
import dopamine.source;

import bindbc.lua;

import std.exception;
import std.string;
import std.stdio;

class Recipe
{
    string name;
    string description;
    string ver;
    string license;
    string copyright;
    string[] langs;
    bool outOfTree;

    Source source;
    BuildSystem build;
}

void initLua()
{
    version (BindBC_Static)
    {
    }
    else
    {
        const ret = loadLua();
        if (ret != luaSupport)
        {
            if (ret == luaSupport.noLibrary)
            {
                throw new Exception("could not find lua library");
            }
            else if (luaSupport.badLibrary)
            {
                throw new Exception("could not find the right lua library");
            }
        }
    }
}

Recipe parseRecipe(string path)
{
    auto L = luaL_newstate();
    luaL_openlibs(L);

    // preloading dop.lua
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");

    lua_pushcfunction(L, &dopModuleLoader);
    lua_setfield(L, -2, "dop");

    // popping package.preload and dopModuleLoader
    lua_pop(L, 2);

    if (luaL_dofile(L, path.toStringz))
    {
        throw new Exception("cannot run Lua file: " ~ fromStringz(lua_tostring(L, -1)).idup);
    }

    auto r = new Recipe;

    r.name = enforce(globalStringVar(L, "name"), "name field is mandatory");
    r.ver = enforce(globalStringVar(L, "version"), "version field is mandatory");
    r.description = globalStringVar(L, "description");
    r.license = globalStringVar(L, "license");
    r.copyright = globalStringVar(L, "copyright");
    r.langs = globalArrayTableVar(L, "langs");
    r.outOfTree = globalBoolVar(L, "out_of_tree");

    r.source = source(globalDictTableVar(L, "source"));
    r.build = buildSystem(globalDictTableVar(L, "build"));

    assert(lua_gettop(L) == 0, "Lua stack not clean");

    lua_close(L);

    return r;

}

private:

int dopModuleLoader(lua_State* L) nothrow
{
    auto dopMod = import("dop.lua");
    luaL_dostring(L, dopMod.ptr);
    return 1;
}

Source source(string[string] aa)
{
    enforce(aa["type"] == "source");

    switch (aa["method"])
    {
    case "git":
        {
            auto url = enforce("url" in aa, "url is mandatory for Git source");
            auto revId = enforce("revId" in aa, "revId is mandatory for Git source");
            auto subdir = "subdir" in aa;
            return new GitSource(*url, *revId, subdir ? *subdir : "");
        }

    default:
        break;
    }

    return null;
}

BuildSystem buildSystem(string[string] aa)
{
    enforce(aa["type"] == "build");

    switch (aa["method"])
    {
    case "meson":
        return new MesonBuildSystem();
    default:
        break;
    }

    return null;
}

string globalStringVar(lua_State* L, string varName, string def = null)
{
    lua_getglobal(L, toStringz(varName));

    scope (success)
        lua_pop(L, 1);

    auto res = getString(L, -1);

    return res ? res : def;
}

bool globalBoolVar(lua_State* L, string varName, bool def = false)
{
    lua_getglobal(L, toStringz(varName));

    scope (success)
        lua_pop(L, 1);

    if (lua_type(L, -1) != LUA_TBOOLEAN)
        return def;

    return lua_toboolean(L, -1) != 0;
}

string[string] globalDictTableVar(lua_State* L, string varName)
{
    lua_getglobal(L, toStringz(varName));
    scope (success)
        lua_pop(L, 1);
    return getStringDictTable(L, -1);
}

string[] globalArrayTableVar(lua_State* L, string varName)
{
    lua_getglobal(L, toStringz(varName));
    scope (success)
        lua_pop(L, 1);
    return getStringArrayTable(L, -1);
}

/// Get a string at index ind in the stack.
string getString(lua_State* L, int ind)
{
    if (lua_type(L, ind) != LUA_TSTRING)
        return null;

    size_t len;
    const ptr = lua_tolstring(L, ind, &len);
    return ptr[0 .. len].idup;
}

/// Get all strings in a table at stack index [ind] who have string keys.
string[string] getStringDictTable(lua_State* L, int ind)
{
    if (lua_type(L, ind) != LUA_TTABLE)
        return null;

    string[string] aa;

    lua_pushnil(L); // first key

    // fixing table ind if relative from top
    if (ind < 0)
        ind -= 1;

    while (lua_next(L, ind) != 0)
    {
        if (lua_type(L, -2) != LUA_TSTRING)
        {
            lua_pop(L, 1);
            continue;
        }

        // uses 'key' (at index -2) and 'value' (at index -1)
        const key = getString(L, -2);
        const val = getString(L, -1);

        if (key && val)
            aa[key] = val;

        // removes 'value'; keeps 'key' for next iteration
        lua_pop(L, 1);
    }

    return aa;
}

/// Get all strings in a table at stack index [ind] who have integer keys.
string[] getStringArrayTable(lua_State* L, int ind)
{
    if (lua_type(L, ind) != LUA_TTABLE)
        return null;

    const len = lua_rawlen(L, ind);

    string[] arr;
    arr.length = len;

    foreach (i; 0 .. len)
    {
        const luaInd = i + 1;
        lua_pushinteger(L, luaInd);
        lua_gettable(L, -2);

        arr[i] = getString(L, -1);

        lua_pop(L, 1);
    }

    return arr;
}

// some debugging functions

void printStack(lua_State* L)
{
    import std.stdio : writefln;
    import std.string : fromStringz;

    const n = lua_gettop(L);
    writefln("Stack has %s elements", n);

    foreach (i; 1 .. n + 1)
    {
        const s = luaL_typename(L, i).fromStringz.idup;
        writef("%s = %s", i, s);
        switch (lua_type(L, i))
        {
        case LUA_TNUMBER:
            writefln(" %g", lua_tonumber(L, i));
            break;
        case LUA_TSTRING:
            writefln(" %s", fromStringz(lua_tostring(L, i)));
            break;
        case LUA_TBOOLEAN:
            writefln(" %s", (lua_toboolean(L, i) ? "true" : "false"));
            break;
        case LUA_TNIL:
            writeln();
            break;
        case LUA_TTABLE:
            //printTable(L, i);
            writefln(" %X", lua_topointer(L, i));
            break;
        case LUA_TFUNCTION:
            {

                lua_Debug d;
                lua_pushvalue(L, i);
                lua_getinfo(L, ">n", &d);
                writefln(" %X - %s", lua_topointer(L, i), d.name.fromStringz);
                break;
            }
        default:
            writefln(" %X", lua_topointer(L, i));
            break;
        }
    }

}

void printTable(lua_State* L, int ind)
{
    import std.stdio : writefln;

    lua_pushnil(L); // first key

    // fixing table ind if relative from top
    if (ind < 0)
        ind -= 1;

    while (lua_next(L, ind) != 0)
    {
        // uses 'key' (at index -2) and 'value' (at index -1)
        const key = getString(L, -2);
        const val = getString(L, -1);

        writefln("[%s] = %s", key, val);

        // removes 'value'; keeps 'key' for next iteration
        lua_pop(L, 1);
    }
}
