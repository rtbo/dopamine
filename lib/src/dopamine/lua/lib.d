module dopamine.lua.lib;

import dopamine.lua.util;

import bindbc.lua;

import std.string;

package(dopamine):

void luaPreloadDopLib(lua_State* L)
{
    // preloading dop.lua
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");

    lua_pushcfunction(L, &luaDopNativeModule);
    lua_setfield(L, -2, "dop_native");

    lua_pushcfunction(L, &luaDopModule);
    lua_setfield(L, -2, "dop");

    // popping package.preload and package
    lua_pop(L, 2);
}

private:

int luaDopModule(lua_State* L) nothrow
{
    import std.path : buildPath, dirName;

    const dopMod = buildPath(dirName(__FILE_FULL_PATH__), "dop.lua");

    if (luaL_dofile(L, dopMod.toStringz) != LUA_OK)
    {
        return luaL_error(L, "Error during 'dop.lua' execution: %s", lua_tostring(L, -1));
    }

    return 1;
}

int luaDopNativeModule(lua_State* L) nothrow
{
    import std.path : dirSeparator, pathSeparator;

    version (linux)
    {
        enum os = "Linux";
    }
    else version (OSX)
    {
        enum os = "OSX";
    }
    else version (Posix)
    {
        enum os = "Posix";
    }
    else version (Windows)
    {
        enum os = "Windows";
    }
    enum posix = os != "Windows";

    const strconsts = [
        "os" : os, "dir_sep" : dirSeparator, "path_sep" : pathSeparator,
    ];
    const boolconsts = ["posix" : posix];
    const funcs = [
        "join_paths" : &luaJoinPaths, "cwd" : &luaCwd, "chdir" : &luaChangeDir,
        "run_cmd" : &luaRunCmd, "profile_environment" : &luaProfileEnvironment,
    ];

    lua_createtable(L, 0, cast(int)(strconsts.length + boolconsts.length + funcs.length));
    const libInd = lua_gettop(L);

    L.catchAll!({
        foreach (k, v; strconsts)
        {
            lua_pushliteral(L, k);
            lua_pushlstring(L, v.ptr, v.length);
            lua_settable(L, libInd);
        }
        foreach (k, v; boolconsts)
        {
            lua_pushliteral(L, k);
            lua_pushboolean(L, v ? 1 : 0);
            lua_settable(L, libInd);
        }
        foreach (k, v; funcs)
        {
            lua_pushliteral(L, k);
            lua_pushcfunction(L, v);
            lua_settable(L, libInd);
        }
    });

    return 1;
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

int luaJoinPaths(lua_State* L) nothrow
{
    import std.path : isAbsolute, dirSeparator;

    luaL_Buffer buf;
    luaL_buffinit(L, &buf);

    const n = lua_gettop(L);
    foreach (i; 1 .. n + 1)
    {
        size_t l;
        const s = luaL_checklstring(L, i, &l);
        if (n > 1 && isAbsolute(s[0 .. l]))
        {
            return luaL_argerror(L, i, "Invalid absolute path after first position");
        }
        if (!s)
            return 0;
        luaL_addlstring(&buf, s, l);
        if (i < n)
        {
            luaL_addlstring(&buf, &dirSeparator[0], dirSeparator.length);
        }
    }

    luaL_pushresult(&buf);
    return 1;
}

int luaCwd(lua_State* L) nothrow
{
    import std.file : getcwd;

    const cwd = L.catchAll!(() => getcwd());

    lua_pushlstring(L, cwd.ptr, cwd.length);
    return 1;
}

int luaChangeDir(lua_State* L) nothrow
{
    import std.file : chdir;

    size_t len;
    const dir = luaL_checklstring(L, 1, &len);
    L.catchAll!({ chdir(dir[0 .. len]); });
    return 0;
}

int luaRunCmd(lua_State* L) nothrow
{
    // take a single table argument:
    // integer keys (array) is the actual command
    // ["workdir"]: working directory
    // ["env"]: additional environment
    // ["allow_fail"]: if true, will return if status is not 0
    // ["catch_output"]: if true, will buffer output and return it to caller
    // return value:
    // if allow_fail and catch_output:
    //      {"status", "output"}
    // if catch_output:
    //      output string
    // if allow_fail:
    //      status integer

    luaL_checktype(L, 1, LUA_TTABLE);

    const len = lua_rawlen(L, 1);
    if (len == 0)
    {
        return luaL_argerror(L, 1, "Invalid empty command");
    }

    string[] cmd;
    cmd.length = len;
    for (int i = 1; i <= len; ++i)
    {
        lua_rawgeti(L, 1, i);
        size_t l;
        const s = luaL_checklstring(L, -1, &l);
        cmd[i - 1] = s[0 .. l].idup;
        lua_pop(L, 1);
    }

    const workDir = luaGetTable!string(L, 1, "workdir", null);

    lua_getfield(L, 1, "env");
    string[string] env = getStringDictTable(L, -1);
    lua_pop(L, 1);

    const allowFail = luaGetTable!bool(L, 1, "allow_fail", false);
    const catchOut = luaGetTable!bool(L, 1, "catch_output", false);

    try
    {
        import dopamine.log : logInfo, info;
        import std.array : join;
        import std.process : Config, execute, spawnProcess, wait;

        int status;
        string output;

        if (catchOut)
        {
            const res = execute(cmd, env, Config.none, size_t.max, workDir);
            status = res.status;
            output = res.output;
        }
        else
        {
            if (workDir)
                logInfo("from directory %s", info(workDir));

            if (cmd.length > 1)
                logInfo("%s %s", info(cmd[0]), cmd[1 .. $].join(" "));
            else
                logInfo("%s", info(cmd[0]));

            auto pid = spawnProcess(cmd, env, Config.none, workDir);
            status = wait(pid);
        }

        if (status != 0 && !allowFail)
            return luaL_error(L, "%s returned %d", cmd[0].toStringz, status);

        if (allowFail && catchOut)
        {
            lua_createtable(L, 0, 2);
            luaSetTable(L, -1, "status", status);
            luaSetTable(L, -1, "output", output);
            return 1;
        }
        if (catchOut)
        {
            luaPush(L, output);
            return 1;
        }
        if (allowFail)
        {
            luaPush(L, status);
            return 1;
        }
        return 0;
    }
    catch (Exception ex)
    {
        return luaL_error(L, ex.msg.toStringz);
    }
}

int luaProfileEnvironment(lua_State* L) nothrow
{
    import dopamine.lua.profile : luaReadProfile;

    luaL_checktype(L, 1, LUA_TTABLE);

    return L.catchAll!({
        auto profile = luaReadProfile(L, 1);

        string[string] env;
        profile.collectEnvironment(env);

        lua_createtable(L, 0, cast(int)env.length);
        foreach (k, v; env)
        {
            luaSetTable(L, -1, k, v);
        }
        return 1;
    });
}
