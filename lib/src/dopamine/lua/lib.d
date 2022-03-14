/// Lua library for dopamine lua files
/// The library is made of two modules:
///     1. the dop_native module implemented in this file
///     2. the dop module implemented in Lua (see dop.lua)
/// The dop module re-exports all symbols of the dop_native module
module dopamine.lua.lib;

import dopamine.lua.util;

import bindbc.lua;

import std.string;
import std.exception;

/// assign `package.preload` such as `local dop = require('dop')` loads
/// the dop lua library.
void luaPreloadDopLib(lua_State* L)
{
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");

    lua_pushcfunction(L, &luaDopNativeModule);
    lua_setfield(L, -2, "dop_native");

    lua_pushcfunction(L, &luaDopModule);
    lua_setfield(L, -2, "dop");

    // popping package.preload and package
    lua_pop(L, 2);

    assert(lua_gettop(L) == 0);
}

/// Load the dop module and assign it to the global `dop` variable
/// Compared to [luaPreloadDopLib], with [luaLoadDopLib] there is no need to `require`
/// the `dop` library from the script, it is already there when the script runs.
void luaLoadDopLib(lua_State* L)
{
    // must start by preloading 'dop_native' because it is required by 'dop'
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");

    lua_pushcfunction(L, &luaDopNativeModule);
    lua_setfield(L, -2, "dop_native");

    // popping package.preload and package
    lua_pop(L, 2);

    // push the dop module on the stack
    cast(void)luaDopModule(L);
    // assign it to the 'dop' global
    lua_setglobal(L, "dop");

    assert(lua_gettop(L) == 0);
}

private:

int luaDopModule(lua_State* L) nothrow
{
    const dopMod = import("dop.lua");

    if (luaL_dostring(L, dopMod.toStringz) != LUA_OK)
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

    // dfmt off
    const strconsts = [
        "os": os,
        "dir_sep": dirSeparator,
        "path_sep": pathSeparator,
    ];
    const boolconsts = ["posix": posix];
    const funcs = [
        "trim": &luaTrim,
        "path": &luaPath,
        "dir_name": &luaDirName,
        "base_name": &luaBaseName,
        "cwd": &luaCwd,
        "chdir": &luaChangeDir,
        "is_file": &luaIsFile,
        "is_dir": &luaIsDir,
        "mkdir": &luaMkdir,
        "copy": &luaCopy,
        "install_file": &luaInstallFile,
        "install_dir": &luaInstallDir,
        "run_cmd": &luaRunCmd,
        "profile_environment": &luaProfileEnvironment,
        "download": &luaDownload,
        "checksum": &luaChecksum,
        "create_archive": &luaCreateArchive,
        "extract_archive": &luaExtractArchive,
    ];
    // dfmt on

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

const(char)[] checkString(lua_State* L, int ind) nothrow
{
    size_t sz;
    auto p = luaL_checklstring(L, ind, &sz);
    return p[0 .. sz];
}

int luaTrim(lua_State* L) nothrow
{
    import std.ascii : isWhite;

    auto s = checkString(L, 1);

    while (s.length && s[0].isWhite)
        s = s[1 .. $];

    while (s.length && s[$ - 1].isWhite)
        s = s[0 .. $ - 1];

    lua_pushlstring(L, s.ptr, s.length);

    return 1;
}

int luaPath(lua_State* L) nothrow
{
    import std.path : isAbsolute, dirSeparator;

    luaL_Buffer buf;
    luaL_buffinit(L, &buf);

    const n = lua_gettop(L);
    foreach (i; 1 .. n + 1)
    {
        size_t l;
        const s = luaL_checklstring(L, i, &l);
        if (i > 1 && isAbsolute(s[0 .. l]))
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

int luaDirName(lua_State* L) nothrow
{
    import std.algorithm : canFind;
    import std.ascii : isAlpha;
    import std.path : dirSeparator, isAbsolute;
    import std.range : repeat;
    import std.string : join;

    version (Windows)
    {
        const dirSeps = "\\/";
    }
    else
    {
        const dirSeps = "/";
    }
    size_t l;
    const ptr = luaL_checklstring(L, 1, &l);

    int num = lua_gettop(L) > 1 ? luaL_checkint(L, 2) : 1;

    return L.catchAll!({
        auto p = ptr[0 .. l];

        const abs = isAbsolute(p);

        while (num > 0)
        {
            if (p.length == 0)
            {
                break;
            }

            // discarding previous trailing sep
            while (p.length && dirSeps.canFind(p[$ - 1]))
                p = p[0 .. $ - 1];

            size_t rem = 0;
            while (p.length > rem && !dirSeps.canFind(p[$ - 1 - rem]))
                rem++;

            const rp = p[$ - rem .. $];
            p = p[0 .. $ - rem];

            if (rp == ".")
                continue; // skip decrem
            else if (rp == "..")
            {
                num++; // one more round needed
                continue;
            }

            num--;
        }

        if (p.length == 0)
        {
            if (abs)
            {
                throw new Exception("dir_name cannot go further than root!");
            }

            if (num > 0)
                p = "..".repeat(num).join(dirSeparator);
            else
                p = ".";
        }
        else
        {
            // Remove last sep if we are not at the root
            assert(dirSeps.canFind(p[$ - 1]));

            version (Windows)
            {
                const isRoot = abs && p.length == 3 && p[0].isAlpha && p[1] == ':'
                    && dirSeps.canFind(p[2]);
            }
            else
            {
                const isRoot = abs && p.length == 1;
            }
            if (!isRoot)
            {
                do
                {
                    p = p[0 .. $ - 1];
                }
                while (dirSeps.canFind(p[$ - 1]));
            }
        }

        luaPush(L, p);
        return 1;
    });
}

int luaBaseName(lua_State* L) nothrow
{
    import std.path : baseName;

    const name = checkString(L, 1);
    return L.catchAll!({ luaPush(L, name.baseName); return 1; });
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

    const dir = checkString(L, 1);
    L.catchAll!({ chdir(dir); });
    return 0;
}

int luaIsFile(lua_State* L) nothrow
{
    import std.file : exists, isFile;

    const f = checkString(L, 1);
    const res = L.catchAll!({ return f.exists && f.isFile; });
    lua_pushboolean(L, res ? 1 : 0);
    return 1;
}

int luaIsDir(lua_State* L) nothrow
{
    import std.file : exists, isDir;

    const d = checkString(L, 1);
    const res = L.catchAll!({ return d.exists && d.isDir; });
    lua_pushboolean(L, res ? 1 : 0);
    return 1;
}

/// Create a directory and return the absolute path of created dir
/// Argument is a table containing a single array entry
/// and optionally a "recurse" named entry
int luaMkdir(lua_State* L) nothrow
{
    import std.file : mkdir, mkdirRecurse;
    import std.path : absolutePath;

    if (lua_type(L, 1) == LUA_TSTRING)
    {
        L.catchAll!({ const dir = luaTo!string(L, 1); mkdir(dir); });
        return 0;
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    return L.catchAll!({
        const dirs = luaReadStringArray(L, 1);
        enforce(dirs.length == 1, "dop.mkdir can only create a single directory");
        const dir = dirs[0];

        const recurse = luaGetTable!bool(L, 1, "recurse", false);

        if (recurse)
            mkdirRecurse(dir);
        else
            mkdir(dir);

        luaPush(L, absolutePath(dir));
        return 1;
    });
}

int luaCopy(lua_State* L) nothrow
{
    import std.file : copy, exists, isDir, isFile;
    import std.path : baseName, buildPath;

    const src = checkString(L, 1);
    auto dest = checkString(L, 2);

    L.catchAll!({
        enforce(
            exists(src) && isFile(src),
            format("dop.copy can only copy files (attempt to copy directory %s)", src)
        );
        if (exists(dest) && isDir(dest))
        {
            dest = buildPath(dest, baseName(src));
        }
        copy(src, dest);
    });

    return 0;
}

int luaInstallFile(lua_State* L) nothrow
{
    import dopamine.util : installFile;

    const src = checkString(L, 1);
    const dest = checkString(L, 2);

    L.catchAll!({ installFile(src, dest); });

    return 0;
}

int luaInstallDir(lua_State* L) nothrow
{
    import dopamine.util : installRecurse;

    const src = checkString(L, 1);
    const dest = checkString(L, 2);

    L.catchAll!({ installRecurse(src, dest); });

    return 0;
}

int luaRunCmd(lua_State* L) nothrow
{
    // take a single table argument:
    // integer keys (array) is the actual command
    // ["workdir"]: working directory
    // ["loglevel"]: log level (one of "info" or "verbose") - default "verbose"
    //               passing false disables the log entirely.
    //               In case of error and allow_fail is false, stderr and stdout
    //               will be logged to the error loglevel
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
    string[string] env = luaReadStringDict(L, -1);
    lua_pop(L, 1);

    const allowFail = luaGetTable!bool(L, 1, "allow_fail", false);
    const catchOut = luaGetTable!bool(L, 1, "catch_output", false);

    // default loglevel to "verbose"
    auto logLevel = luaGetTable!string(L, 1, "loglevel", "verbose");
    // if false was passed: disable logging
    if (!luaGetTable!bool(L, 1, "loglevel", true))
        logLevel = null;

    try
    {
        import dopamine.log : log, LogLevel, info, minLogLevel;
        import std.array : join;
        import std.process : Config, execute, spawnProcess, wait;

        int status;
        string output;
        string stdoutLog;
        string stderrLog;

        LogLevel ll;

        if (logLevel)
        {
            switch (logLevel)
            {
            case "info":
                ll = LogLevel.info;
                break;
            case "verbose":
                ll = LogLevel.verbose;
                break;
            default:
                throw new Exception("invalid log level: " ~ logLevel);
            }

            if (workDir)
                log(ll, "from directory %s", info(workDir));

            if (cmd.length > 1)
                log(ll, "%s %s", info(cmd[0]), cmd[1 .. $].join(" "));
            else
                log(ll, "%s", info(cmd[0]));
        }

        if (catchOut)
        {
            const res = execute(cmd, env, Config.none, size_t.max, workDir);
            status = res.status;
            output = res.output;
            if (logLevel && ll >= minLogLevel)
            {
                log(ll, output);
            }
        }
        else
        {
            import dopamine.util : tempPath;
            import std.stdio : stdin, stderr, stdout, File;

            version (Windows)
                enum nullFile = "NUL";
            else
                enum nullFile = "/dev/null";

            auto childStdout = stdout;
            auto childStderr = stderr;
            auto config = Config.retainStdout | Config.retainStderr;

            if (!logLevel || ll < minLogLevel)
            {
                // no logging requested, we either send to null, or we cache in logfile to report later
                config = Config.none;

                if (allowFail)
                {
                    childStdout = File(nullFile, "w");
                    childStderr = File(nullFile, "w");
                }
                else
                {
                    stdoutLog = tempPath(null, "stdout", ".txt");
                    stderrLog = tempPath(null, "stderr", ".txt");
                    childStdout = File(stdoutLog, "w");
                    childStderr = File(stderrLog, "w");
                }
            }

            auto pid = spawnProcess(cmd, stdin, childStdout, childStderr, env, config, workDir);
            status = wait(pid);
        }

        if (status != 0 && !allowFail)
        {
            import std.file : read;

            auto msg = format("%s returned %d.", cmd[0], status);
            if (stdoutLog)
            {
                const content = cast(const(char)[]) read(stdoutLog);
                msg ~= "\n----- command stdout -----\n" ~ content;
            }
            if (stderrLog)
            {
                const content = cast(const(char)[]) read(stderrLog);
                msg ~= "\n----- command stderr -----\n" ~ content;
            }
            msg ~= '\0';
            return luaL_error(L, &msg[0]);
        }

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

        lua_createtable(L, 0, cast(int) env.length);
        foreach (k, v; env)
        {
            luaSetTable(L, -1, k, v);
        }
        return 1;
    });
}

int luaDownload(lua_State* L) nothrow
{
    import std.net.curl : download;

    luaL_checktype(L, 1, LUA_TTABLE);

    return L.catchAll!({
        const url = luaGetTable!string(L, 1, "url");
        const dest = luaGetTable!string(L, 1, "dest");

        download(url, dest);
        return 0;
    });
}

int luaChecksum(lua_State* L) nothrow
{
    import std.algorithm : canFind;
    import std.digest : Digest, toHexString, LetterCase;
    import std.digest.md : MD5Digest;
    import std.digest.sha : SHA1Digest, SHA256Digest, secureEqual;
    import std.stdio : File;
    import std.string : toLower;

    luaL_checktype(L, 1, LUA_TTABLE);

    const files = luaReadStringArray(L, 1);
    if (files.length == 0)
    {
        return luaL_error(L, "dop.checksum must have at least one argument");
    }

    return L.catchAll!({

        lua_pushnil(L);
        while (lua_next(L, 1))
        {
            // skip numeric indices
            if (lua_type(L, -2) != LUA_TSTRING)
            {
                lua_pop(L, 1);
                continue;
            }

            const key = luaTo!string(L, -2);
            enforce(["md5", "sha1", "sha256"].canFind(key), "unsupported checksum: " ~ key);

            string[] vals;
            switch (lua_type(L, -1))
            {
            case LUA_TSTRING:
                vals = [luaTo!string(L, -1)];
                break;
            case LUA_TTABLE:
                vals = luaReadStringArray(L, -1);
                break;
            default:
                throw new Exception("invalid checksum spec: " ~ key);
            }
            enforce(files.length == vals.length,
                "must provide as many entries in " ~ key ~ " than there are files to check");

            Digest digest;

            switch (key)
            {
            case "md5":
                digest = new MD5Digest();
                break;
            case "sha1":
                digest = new SHA1Digest();
                break;
            case "sha256":
                digest = new SHA256Digest();
                break;
            default:
                assert(false);
            }

            foreach (i, f; files)
            {
                digest.reset();
                auto file = File(f, "rb");
                foreach (chunk; file.byChunk(4096))
                {
                    digest.put(chunk);
                }
                const hash = digest.finish().toHexString!(LetterCase.lower)();
                enforce(vals[i].toLower() == hash, key ~ " checksum failed for " ~ f);
            }

            lua_pop(L, 1);
        }

        return 0;
    });
}

int luaCreateArchive(lua_State* L) nothrow
{
    import dopamine.archive : ArchiveBackend;

    luaL_checktype(L, 1, LUA_TTABLE);

    return L.catchAll!({
        const indir = luaGetTable!string(L, 1, "indir");
        const archive = luaGetTable!string(L, 1, "archive");

        ArchiveBackend.get.create(indir, archive);
        return 0;
    });
}

int luaExtractArchive(lua_State* L) nothrow
{
    import dopamine.archive : ArchiveBackend;

    luaL_checktype(L, 1, LUA_TTABLE);

    return L.catchAll!({
        const archive = luaGetTable!string(L, 1, "archive");
        const outdir = luaGetTable!string(L, 1, "outdir");

        ArchiveBackend.get.extract(archive, outdir);
        return 0;
    });
}
