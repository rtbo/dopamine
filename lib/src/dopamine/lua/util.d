module dopamine.lua.util;

import bindbc.lua;

import std.exception;
import std.stdio;
import std.string;
import std.traits;

int positiveStackIndex(lua_State* L, int index) nothrow
{
    pragma(inline, true);

    return index >= 0 || index == LUA_REGISTRYINDEX ? index : lua_gettop(L) + index + 1;
}

void luaAddPrefixToPath(lua_State* L, string prefix)
{
    import std.format : format;

    const addedpath = ";%s/?.lua;%s/?/init.lua".format(prefix, prefix);

    lua_getglobal(L, "package");
    lua_getfield(L, -1, "path");
    const lp = luaPop!string(L) ~ addedpath;
    luaSetTable(L, -1, "path", lp);
    lua_pop(L, 1);
}

enum isLuaScalar(T) = (isSomeString!T || isNumeric!T || is(T == bool));

void luaPush(T)(lua_State* L, T value) nothrow if (isLuaScalar!T)
{
    pragma(inline, true);

    static if (isSomeString!T)
    {
        lua_pushlstring(L, value.ptr, value.length);
    }
    else static if (is(T == bool))
    {
        lua_pushboolean(L, value ? 1 : 0);
    }
    else static if (isIntegral!T)
    {
        lua_pushinteger(L, cast(lua_Integer) value);
    }
    else static if (isFloatingPoint!T)
    {
        lua_pushnumber(L, cast(lua_Number) value);
    }
}

T luaTo(T)(lua_State* L, int index) if (isLuaScalar!T)
{
    static if (isSomeString!T)
    {
        enforce(lua_type(L, index) == LUA_TSTRING, "string expected");
        size_t l;
        const s = lua_tolstring(L, index, &l);
        return s[0 .. l].idup;
    }
    else static if (is(T == bool))
    {
        enforce(lua_type(L, index) == LUA_TBOOLEAN, "boolean expected");
        return lua_toboolean(L, index) != 0;
    }
    else static if (isIntegral!T)
    {
        enforce(lua_type(L, index) == LUA_TNUMBER, "number expected");
        return cast(T) lua_tointeger(L, index);
    }
    else static if (isFloatingPoint!T)
    {
        enforce(lua_type(L, index) == LUA_TNUMBER, "number expected");
        return cast(T) lua_tonumber(L, index);
    }
}

T luaTo(T)(lua_State* L, int index, T defaultVal) nothrow if (isLuaScalar!T)
{
    static if (isSomeString!T)
    {
        if (lua_type(L, index) != LUA_TSTRING)
            return defaultVal;
        size_t l;
        const s = lua_tolstring(L, index, &l);
        return s[0 .. l].idup;
    }
    else static if (is(T == bool))
    {
        if (lua_type(L, index) != LUA_TBOOLEAN)
            return defaultVal;
        return lua_toboolean(L, index) != 0;
    }
    else static if (isIntegral!T)
    {
        if (lua_type(L, index) != LUA_TNUMBER)
            return defaultVal;
        return cast(T) lua_tointeger(L, index);
    }
    else static if (isFloatingPoint!T)
    {
        if (lua_type(L, index) != LUA_TNUMBER)
            return defaultVal;
        return cast(T) lua_tonumber(L, index);
    }
}

/// same as luaTo!string, but allows for casting to string
string luaToString(lua_State* L, int index)
{
    size_t l;
    const s = lua_tolstring(L, index, &l);
    return s[0 .. l].idup;
}

T luaPop(T)(lua_State* L) if (isLuaScalar!T)
{
    scope (success)
        lua_pop(L, 1);
    return luaTo!T(L, -1);
}

T luaPop(T)(lua_State* L, T defaultVal) nothrow if (isLuaScalar!T)
{
    scope (success)
        lua_pop(L, 1);
    return luaTo!T(L, -1, defaultVal);
}

T luaGetTable(T)(lua_State* L, int tableInd, string key)
{
    lua_getfield(L, tableInd, key.toStringz);
    return luaPop!T(L);
}

T luaGetTable(T)(lua_State* L, int tableInd, string key, T defaultVal) nothrow
{
    lua_getfield(L, tableInd, key.toStringz);
    return luaPop!T(L, defaultVal);
}

void luaSetTable(T)(lua_State* L, int tableInd, string key, T value) nothrow
        if (isLuaScalar!T)
{
    tableInd = positiveStackIndex(L, tableInd);
    lua_pushlstring(L, key.ptr, key.length);
    luaPush(L, value);
    lua_settable(L, tableInd);
}

T luaGetGlobal(T)(lua_State* L, string varName) if (isLuaScalar!T)
{
    lua_getglobal(L, toStringz(varName));
    return luaPop!T(L);
}

T luaGetGlobal(T)(lua_State* L, string varName, T defaultVal) nothrow
        if (isLuaScalar!T)
{
    lua_getglobal(L, toStringz(varName));
    return luaPop!T(L, defaultVal);
}

/// Call fun with global variable [varName] pushed on top of the stack.
/// Stack is popped when fun returns.
auto luaWithGlobal(string varName, alias fun)(lua_State* L)
{
    lua_getglobal(L, toStringz(varName));
    scope (success)
        lua_pop(L, 1);

    static if (is(typeof(fun()) == void))
        fun();
    else
        return fun();
}

/// Get all strings in a table at stack index [ind] who have string keys.
string[string] luaReadStringDict(lua_State* L, int ind) nothrow
{
    if (lua_type(L, ind) != LUA_TTABLE)
        return null;

    string[string] aa;

    ind = positiveStackIndex(L, ind);

    lua_pushnil(L); // first key

    while (lua_next(L, ind) != 0)
    {
        // skip numeric indices
        if (lua_type(L, -2) != LUA_TSTRING)
        {
            lua_pop(L, 1);
            continue;
        }

        // uses 'key' (at index -2) and 'value' (at index -1)
        const key = luaTo!string(L, -2, null);
        const val = luaTo!string(L, -1, null);

        if (key && val)
            aa[key] = val;

        // removes 'value'; keeps 'key' for next iteration
        lua_pop(L, 1);
    }

    return aa;
}

/// Get all strings in a table at stack index [ind] who have integer keys.
string[] luaReadStringArray(lua_State* L, int ind) nothrow
{
    if (lua_type(L, ind) != LUA_TTABLE)
        return null;

    ind = positiveStackIndex(L, ind);

    const len = lua_rawlen(L, ind);

    string[] arr;
    arr.length = len;

    for (int i = 1; i <= len; ++i)
    {
        lua_rawgeti(L, ind, i);

        arr[i - 1] = luaTo!string(L, -1, null);

        lua_pop(L, 1);
    }

    return arr;
}

// some debugging functions

void luaPrintStack(lua_State* L, File output)
{
    import std.string : fromStringz;

    const n = lua_gettop(L);
    output.writefln("Stack has %s elements", n);

    foreach (i; 1 .. n + 1)
    {
        const s = luaL_typename(L, i).fromStringz.idup;
        output.writef("%s = %s", i, s);
        switch (lua_type(L, i))
        {
        case LUA_TNUMBER:
            output.writefln(" %g", lua_tonumber(L, i));
            break;
        case LUA_TSTRING:
            output.writefln(" %s", fromStringz(lua_tostring(L, i)));
            break;
        case LUA_TBOOLEAN:
            output.writefln(" %s", (lua_toboolean(L, i) ? "true" : "false"));
            break;
        case LUA_TNIL:
            output.writeln();
            break;
        case LUA_TTABLE:
            //printTable(L, i);
            output.writefln(" %X", lua_topointer(L, i));
            break;
        case LUA_TFUNCTION:
            {

                lua_Debug d;
                lua_pushvalue(L, i);
                lua_getinfo(L, ">n", &d);
                output.writefln(" %X - %s", lua_topointer(L, i), d.name.fromStringz);
                break;
            }
        default:
            output.writefln(" %X", lua_topointer(L, i));
            break;
        }
    }

}

void luaPrintTable(lua_State* L, int ind)
{
    import std.stdio : writefln;

    lua_pushnil(L); // first key

    // fixing table ind if relative from top
    if (ind < 0)
        ind -= 1;

    while (lua_next(L, ind) != 0)
    {
        // uses 'key' (at index -2) and 'value' (at index -1)
        const key = luaTo!string(L, -2);
        const val = luaTo!string(L, -1);

        writefln("[%s] = %s", key, val);

        // removes 'value'; keeps 'key' for next iteration
        lua_pop(L, 1);
    }
}
