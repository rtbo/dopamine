module dopamine.recipe;

import dopamine.build;
import dopamine.source;
import dopamine.dependency;

import bindbc.lua;

import std.exception;
import std.string;

class Recipe
{
    string name;
    string description;
    string ver;
    string license;
    string copyright;
    string[] langs;

    Dependency[] dependencies;
    Source source;
    BuildSystem build;
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

    if (luaL_dofile(L, path.toStringz)) {
        throw new Exception ("cannot run Lua file: " ~ fromStringz(lua_tostring(L, -1)).idup);
    }

    auto r = new Recipe;

    r.name = enforce(globalStringVar(L, "name"), "name field is mandatory");
    r.ver = enforce(globalStringVar(L, "version"), "version field is mandatory");
    r.description = globalStringVar(L, "description");
    r.license = globalStringVar(L, "license");
    r.copyright = globalStringVar(L, "copyright");
    r.langs = globalTableVar(L, "langs").values;

    r.source = source(globalTableVar(L, "source"));
    r.build = buildSystem(globalTableVar(L, "source"));

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
    enforce (aa["type"] == "source");

    switch (aa["method"]) {
    case "git":
        return new GitSource(aa["url"], aa["revId"], aa["subdir"]);
    default:
        break;
    }

    return null;
}

BuildSystem buildSystem(string[string] aa)
{
    enforce (aa["type"] == "build");

    switch (aa["method"]) {
    case "meson":
        return new MesonBuildSystem();
    default:
        break;
    }

    return null;
}

string globalStringVar(lua_State* L, string varName)
{
    lua_getglobal(L, toStringz(varName));
    return getString(L, -1);
}

string[string] globalTableVar(lua_State* L, string varName)
{
    lua_getglobal(L, toStringz(varName));
    return getStringTable(L, -1);
}


/// Get a string at index ind in the stack.
string getString(lua_State* L, int ind)
{
    if (lua_type(L, ind) != LUA_TSTRING) return null;

    size_t len;
    const ptr = lua_tolstring(L, ind, &len);
    return ptr[ 0 .. len ].idup;
}

/// Get a table with string values at index ind in the stack.
string[string] getStringTable(lua_State* L, int ind)
{
    import std.stdio;
    if (lua_type(L, ind) != LUA_TTABLE) return null;

    string[string] aa;

    lua_pushnil(L);  // first key
    while (lua_next(L, ind) != 0)
    {
        // uses 'key' (at index -2) and 'value' (at index -1)
        const key = getString(L, -2);
        const val = getString(L, -1);

        writefln("%1 = %1", key, val);
        if (key && val)
            aa[key] = val;

        // removes 'value'; keeps 'key' for next iteration
        lua_pop(L, 1);
    }

    return aa;
}

// some debugging functions

void printStack(lua_State* L)
{
    import std.stdio : writefln;
    import std.string : fromStringz;

    int n = lua_gettop(L);
    foreach (i; 1 .. n+1) {
        const s = luaL_typename(L, i).fromStringz.idup;
        writefln("%s = %s", i, s);
        switch (lua_type(L, i)) {
        case LUA_TNUMBER:
            writefln("%g",lua_tonumber(L,i));
            break;
        case LUA_TSTRING:
            writefln("%s",lua_tostring(L,i));
            break;
        case LUA_TBOOLEAN:
            writefln("%s", (lua_toboolean(L, i) ? "true" : "false"));
            break;
        case LUA_TNIL:
            writefln("%s", "nil");
            break;
        case LUA_TTABLE:
            printTable(L, i);
            break;
        default:
            writefln("%X",lua_topointer(L,i));
            break;
        }
    }

}

void printTable(lua_State *L, int ind)
{
    import std.stdio : writefln;

    /* table is in the stack at index 't' */
     lua_pushnil(L);  /* first key */
     while (lua_next(L, ind) != 0)
     {
       /* uses 'key' (at index -2) and 'value' (at index -1) */
        const key = getString(L, -2);
        const val = getString(L, -1);

        writefln("[%s] = %s", key, val);

       /* removes 'value'; keeps 'key' for next iteration */
       lua_pop(L, 1);
     }
}
