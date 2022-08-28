module dopamine.lua.profile;

import dopamine.c.lua;
import dopamine.lua.util;
import dopamine.msvc;
import dopamine.profile;
import dopamine.semver;

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

    lua_pushliteral(L, "tools");
    lua_createtable(L, 0, cast(int) profile.tools.length);
    const toolsInd = lua_gettop(L);
    foreach (const ref tool; profile.tools)
    {
        const id = tool.id;
        lua_pushlstring(L, id.ptr, id.length);

        lua_createtable(L, 0, 3);
        const toolInd = lua_gettop(L);
        luaSetTable(L, toolInd, "name", tool.name);
        luaSetTable(L, toolInd, "version", tool.ver);
        luaSetTable(L, toolInd, "path", tool.path);
        version (Windows)
        {
            if (tool.vsvc)
            {
                luaSetTable(L, toolInd, "msvc", true);
                luaSetTable(L, toolInd, "msvc_ver", tool.vsvc.productLineVersion);
                luaSetTable(L, toolInd, "msvc_disp", tool.vsvc.displayName);
            }
        }

        lua_settable(L, toolsInd);
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

    lua_getfield(L, ind, "tools");
    const toolInd = lua_gettop(L);
    enforce(lua_type(L, -1) == LUA_TTABLE, "Cannot find tools profile table");
    Tool[] tools;
    lua_pushnil(L);
    while (lua_next(L, toolInd) != 0)
    {
        enforce(lua_type(L, -2) == LUA_TSTRING, "Tools table key must be the tool id");

        const id = luaTo!string(L, -2);

        // tool table at index -1
        const name = luaGetTable!string(L, -1, "name");
        const ver = luaGetTable!string(L, -1, "version");
        const path = luaGetTable!string(L, -1, "path");

        version (Windows)
        {
            const msvc = luaGetTable!bool(L, -1, "msvc", false);
            if (msvc)
            {
                VsVcInstall install;
                install.installPath = path;
                install.ver = Semver(ver);
                install.productLineVersion = luaGetTable!string(L, -1, "msvc_ver");
                install.displayName = luaGetTable!string(L, -1, "msvc_disp");

                tools ~= Tool(id, install);
                lua_pop(L, 1);
                continue;
            }
        }

        tools ~= Tool(id, name, ver, path);

        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    const hash = luaGetTable!string(L, ind, "digest_hash");

    auto profile = new Profile(basename, host, buildType, tools);

    enforce(hash == profile.digestHash,
            "Error: hash mismatch between profile rebuilt from Lua and original");

    return profile;
}

@("Profile can pass to lua and come back identical")
unittest
{
    auto L = luaL_newstate();
    scope (exit)
        lua_close(L);

    auto profile = mockProfileLinux();
    luaPushProfile(L, profile);
    auto copy = luaReadProfile(L, -1);

    assert(profile.name == copy.name);
    assert(profile.digestHash == copy.digestHash);
}
