module dopamine.c.lua.macros;

import dopamine.c.lua.bindings;
import dopamine.c.lua.defs;

nothrow @nogc @system:

// lua.h

int lua_upvalueindex(int i)
{
    pragma(inline, true)
    return LUA_REGISTRYINDEX - i;
}

void lua_call(lua_State* L, int nargs, int nresults)
{
    pragma(inline, true)
    return lua_callk(L, nargs, nresults, 0, null);
}

int lua_pcall(lua_State* L, int nargs, int nresults, int errfunc)
{
    pragma(inline, true)
    return lua_pcallk(L, nargs, nresults, errfunc, 0, null);
}

int lua_yield(lua_State* L, int nresults)
{
    pragma(inline, true)
    return lua_yieldk(L, nresults, 0, null);
}

void* lua_getextraspace(lua_State* L)
{
    pragma(inline, true)
    return cast(void*)((cast(char*) L) - LUA_EXTRASPACE);
}

lua_Number lua_tonumber(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_tonumberx(L, idx, null);
}

lua_Integer lua_tointeger(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_tointegerx(L, idx, null);
}

void lua_pop(lua_State* L, int n)
{
    pragma(inline, true)
    lua_settop(L, -n - 1);
}

void lua_newtable(lua_State* L)
{
    pragma(inline, true)
    lua_createtable(L, 0, 0);
}

void lua_register(lua_State* L, const(char)* name, lua_CFunction fn)
{
    pragma(inline, true)
    lua_pushcfunction(L, fn);
    lua_setglobal(L, name);
}

void lua_pushcfunction(lua_State* L, lua_CFunction fn)
{
    pragma(inline, true)
    lua_pushcclosure(L, fn, 0);
}

bool lua_isfunction(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_type(L, idx) == LUA_TFUNCTION;
}

bool lua_istable(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_type(L, idx) == LUA_TTABLE;
}

bool lua_islightuserdata(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_type(L, idx) == LUA_TLIGHTUSERDATA;
}

bool lua_isnil(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_type(L, idx) == LUA_TNIL;
}

bool lua_isboolean(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_type(L, idx) == LUA_TBOOLEAN;
}

bool lua_isthread(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_type(L, idx) == LUA_TTHREAD;
}

bool lua_isnone(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_type(L, idx) == LUA_TNONE;
}

bool lua_isnoneornil(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_type(L, idx) <= 0;
}

void lua_pushliteral(lua_State* L, const(char)[] s)
{
    pragma(inline, true)
    lua_pushlstring(L, s.ptr, s.length);
}

void lua_pushglobaltable(lua_State* L)
{
    pragma(inline, true)
    lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS);
}

const(char)* lua_tostring(lua_State* L, int i)
{
    pragma(inline, true)
    return lua_tolstring(L, i, null);
}

void lua_insert(lua_State* L, int idx)
{
    pragma(inline, true)
    lua_rotate(L, idx, 1);
}

void lua_remove(lua_State* L, int idx)
{
    pragma(inline, true)
    lua_rotate(L, idx, -1);
    lua_pop(L, 1);
}

void lua_replace(lua_State* L, int idx)
{
    pragma(inline, true)
    lua_copy(L, -1, idx);
    lua_pop(L, 1);
}

// lauxlib.h

void luaL_newlibtable(lua_State* L, const(luaL_Reg)[] l)
{
    pragma(inline, true)
    lua_createtable(L, 0, cast(int) l.length - 1);
}

void luaL_newlib(lua_State* L, const(luaL_Reg)[] l)
{
    pragma(inline, true)
    luaL_checkversion(L);
    luaL_newlibtable(L, l);
    luaL_setfuncs(L, l.ptr, 0);
}

void luaL_argcheck(lua_State* L, bool cond, int arg, const(char)* extramsg)
{
    pragma(inline, true)if (!cond)
        luaL_argerror(L, arg, extramsg);
}

void luaL_argexpected(lua_State* L, bool cond, int arg, const(char)* tname)
{
    pragma(inline, true)
    if (!cond)
        luaL_typeerror(L, arg, tname);
}

const(char)* luaL_checkstring(lua_State* L, int arg)
{
    pragma(inline, true)
    return luaL_checklstring(L, arg, null);
}

const(char)* luaL_optstring(lua_State* L, int arg, const(char)* def)
{
    pragma(inline, true)
    return luaL_optlstring(L, arg, def, null);
}

const(char)* luaL_typename(lua_State* L, int idx)
{
    pragma(inline, true)
    return lua_typename(L, lua_type(L, idx));
}

bool luaL_dofile(lua_State* L, const(char)* filename)
{
    pragma(inline, true)
    return luaL_loadfile(L, filename) != 0 || lua_pcall(L, 0, LUA_MULTRET, 0) != 0;
}

bool luaL_dostring(lua_State* L, const(char)* str)
{
    pragma(inline, true)
    return luaL_loadstring(L, str) != 0 || lua_pcall(L, 0, LUA_MULTRET, 0) != 0;
}

void luaL_getmetatable(lua_State* L, const(char)* tname)
{
    pragma(inline, true)
    lua_getfield(L, LUA_REGISTRYINDEX, tname);
}

// #define luaL_opt(L,f,n,d)	(lua_isnoneornil(L,(n)) ? (d) : f(L,(n)))

int luaL_loadbuffer(lua_State* L, const(char)* buff, size_t sz, const(char)* name)
{
    pragma(inline, true)
    return luaL_loadbufferx(L, buff, sz, name, null);
}

void luaL_pushfail(lua_State* L)
{
    pragma(inline, true)
    lua_pushnil(L);
}

size_t luaL_bufflen(luaL_Buffer* bf)
{
    pragma(inline, true)
    return bf.n;
}

char* luaL_buffaddr(luaL_Buffer* bf)
{
    pragma(inline, true)
    return bf.b;
}

void luaL_addchar(luaL_Buffer* B, char c)
{
    pragma(inline, true)
    if (B.n < B.size || luaL_prepbuffsize(B, 1))
        B.b[B.n++] = c;
}

void luaL_addsize(luaL_Buffer* B, size_t s)
{
    pragma(inline, true)
    B.n += s;
}

void luaL_buffsub(luaL_Buffer* B, size_t s)
{
    pragma(inline, true)
    B.n -= s;
}

int luaL_loadfile(lua_State* L, const(char)* filename)
{
    pragma(inline, true)
    return luaL_loadfilex(L, filename, null);
}

char* luaL_prepbuffer(luaL_Buffer* B)
{
    pragma(inline, true)
    return luaL_prepbuffsize(B, LUAL_BUFFERSIZE);
}

void luaL_checkversion(lua_State* L)
{
    luaL_checkversion_(L, LUA_VERSION_NUM, LUAL_NUMSIZES);
}