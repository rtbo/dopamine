/// Module defining the Dopamine recipe format.
module dopamine.recipe.dop;

import dopamine.recipe;
import dopamine.dep.spec;
import dopamine.lua.lib;
import dopamine.lua.profile;
import dopamine.lua.util;
import dopamine.profile;
import dopamine.semver;

import dopamine.c.lua;

import std.exception;
import std.file;
import std.path;
import std.string;

/// Parse a dopamine recipe file.
/// A revision can be specified directly if it is known
/// e.g. loading from a cache directory.
DopRecipe parseDopRecipe(string filename, string root, string revision)
{
    auto L = luaL_newstate();
    luaL_openlibs(L);
    luaLoadDopLib(L);

    assert(lua_gettop(L) == 0);

    if (luaL_dofile(L, filename.toStringz))
    {
        throw new Exception("cannot parse package recipe file: " ~ luaPop!string(L));
    }

    enforce(
        lua_gettop(L) == 0,
        "Recipes should not return anything"
    );

    return new DopRecipe(L, root, revision);
}

/// The Dopamine Lua based recipe type.
/// This recipe is supported by Lua script that define recipe info and functions
/// through global Lua variables.
/// The recipe can use the Lua standard library as well as the
/// `dop` lua module provided by dopamine and pre-loaded when the script
/// is execute_
final class DopRecipe : Recipe
{
    string _name;
    string _description;
    Semver _ver;
    string _license;
    string _copyright;
    string _upstreamUrl;
    string[] _tools;
    string[] _included;

    DepSpec[] _dependencies;
    string[] _funcs;
    string _inTreeSrc;
    bool _stageFalse;

    string _rootDir;
    bool _isLight;
    string _revision;
    string[] _allFiles;

    lua_State* L;

    private this(lua_State* L, string rootDir, string revision)
    in (isAbsolute(rootDir))
    {
        this.L = L;
        _rootDir = buildNormalizedPath(rootDir);

        // start with the build function because it determines whether
        // it is a light recipe or package recipe
        {
            lua_getglobal(L, "build");
            scope (exit)
                lua_pop(L, 1);

            switch (lua_type(L, -1))
            {
            case LUA_TFUNCTION:
                _funcs ~= "build";
                break;
            case LUA_TNIL:
                _isLight = true;
                break;
            default:
                throw new Exception("Invalid 'build' field: expected a function");
            }
        }
        // tools and dependencies are needed regardless of recipe type
        {
            lua_getglobal(L, "tools");
            scope (exit)
                lua_pop(L, 1);

            _tools = luaReadStringArray(L, -1);
        }
        {
            lua_getglobal(L, "dependencies");
            scope (exit)
                lua_pop(L, 1);

            switch (lua_type(L, -1))
            {
            case LUA_TFUNCTION:
                _funcs ~= "dependencies";
                break;
            case LUA_TTABLE:
                _dependencies = readDependencies(L);
                break;
            case LUA_TNIL:
                enforce(
                    !_isLight,
                    "Light recipe without dependency"
                );
                break;
            default:
                throw new Exception("invalid dependencies specification");
            }
        }

        if (!_isLight)
        {
            _name = enforce(
                luaGetGlobal!string(L, "name", null),
                "The name field is mandatory in the recipe"
            );
            const verStr = enforce(
                luaGetGlobal!string(L, "version", null),
                "The version field is mandatory in the recipe"
            );
            _ver = verStr ? Semver(verStr) : Semver.init;
            _description = luaGetGlobal!string(L, "description", null);
            _license = luaGetGlobal!string(L, "license", null);
            _copyright = luaGetGlobal!string(L, "copyright", null);
            _upstreamUrl = luaGetGlobal!string(L, "upstream_url", null);

            if (revision)
                _revision = revision;

            {
                lua_getglobal(L, "include");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TTABLE:
                    _included = luaReadStringArray(L, -1);
                    break;
                case LUA_TSTRING:
                    _included = [luaTo!string(L, -1)];
                    break;
                case LUA_TFUNCTION:
                    _funcs ~= "include";
                    break;
                case LUA_TNIL:
                    break;
                default:
                    throw new Exception(
                        "Invalid 'include' key: expected a function, a table, a string or nil");
                }
            }

            {
                lua_getglobal(L, "source");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TSTRING:
                    _inTreeSrc = luaTo!string(L, -1);
                    enforce(!isAbsolute(_inTreeSrc),
                        "constant source must be relative to package file");
                    break;
                case LUA_TFUNCTION:
                    _funcs ~= "source";
                    break;
                case LUA_TNIL:
                    _inTreeSrc = ".";
                    break;
                default:
                    throw new Exception(
                        "Invalid 'source' key: expected a function, a string or nil");
                }
            }
            {
                lua_getglobal(L, "stage");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TFUNCTION:
                    _funcs ~= "stage";
                    break;
                case LUA_TBOOLEAN:
                    import dopamine.log : logWarningH;

                    if (!luaTo!bool(L, -1))
                        _stageFalse = true;
                    else
                        logWarningH("%s/%s: `stage = true` has no effect.", name, ver);
                    break;
                case LUA_TNIL:
                    break;
                default:
                    throw new Exception("Invalid 'stage' field: expected a function or boolean");
                }
            }
            {
                lua_getglobal(L, "post_stage");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TFUNCTION:
                    _funcs ~= "post_stage";
                    break;
                case LUA_TNIL:
                    break;
                default:
                    throw new Exception("Invalid 'post_stage' field: expected a function");
                }
            }
        }

        assert(lua_gettop(L) == 0, "Lua stack not clean");
    }

    ~this()
    {
        lua_close(L);
    }

    @property RecipeType type() const @safe
    {
        return RecipeType.dop;
    }

    @property bool isLight() const @safe
    {
        return _isLight;
    }

    @property string name() const @safe
    {
        return _name;
    }

    @property Semver ver() const @safe
    {
        return _ver;
    }

    @property string revision() const @safe
    {
        return _revision;
    }

    @property void revision(string rev) @safe
    {
        _revision = rev;
    }

    @property string description() const @safe
    {
        return _description;
    }

    @property string license() const @safe
    {
        return _license;
    }

    @property string upstreamUrl() const @safe
    {
        return _upstreamUrl;
    }

    @property const(string)[] tools() const @safe
    {
        return _tools;
    }

    @property bool hasDependencies() const @safe
    {
        return hasFunction("dependencies") || _dependencies.length != 0;
    }

    const(DepSpec)[] dependencies(const(Profile) profile) @system
    {
        if (!hasFunction("dependencies"))
            return _dependencies;

        lua_getglobal(L, "dependencies");

        const nargs = 1;
        const funcPos = 1;

        assert(lua_type(L, funcPos) == LUA_TFUNCTION);

        luaPushProfile(L, profile);

        const cwd = getcwd();
        chdir(_rootDir);
        scope(exit)
            chdir(cwd);

        if (lua_pcall(L, nargs, /* nresults = */ 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot get dependencies: " ~ luaPop!string(L));
        }

        scope (success)
            lua_pop(L, 1);

        return readDependencies(L);
    }

    string[] include() @system
    {
        if (_included)
            return _included;

        lua_getglobal(L, "include");
        if (lua_type(L, -1) == LUA_TNIL)
        {
            lua_pop(L, 1);
            return null;
        }

        assert(lua_type(L, -1) == LUA_TFUNCTION,
            "function expected for 'include'"
        );

        const cwd = getcwd();
        chdir(_rootDir);
        scope(exit)
            chdir(cwd);

        if (lua_pcall(L, 0, 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot get files included with recipe: " ~ luaPop!string(L));
        }

        _included = luaReadStringArray(L, -1);
        lua_pop(L, 1);
        return _included;
    }

    @property bool inTreeSrc() const @safe
    {
        return _inTreeSrc.length > 0;
    }

    string source() @system
    {
        if (_inTreeSrc)
            return _inTreeSrc;

        lua_getglobal(L, "source");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a source function");

        const cwd = getcwd();
        chdir(_rootDir);
        scope(exit)
            chdir(cwd);

        if (lua_pcall(L, /* nargs = */ 0, /* nresults = */ 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot get source: " ~ luaPop!string(L));
        }

        return L.luaPop!string();
    }

    void build(BuildDirs dirs, BuildConfig config, DepInfo[string] depInfos = null) @system
    {
        assert(buildNormalizedPath(dirs.root) == buildNormalizedPath(_rootDir));

        lua_getglobal(L, "build");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a build function");

        pushBuildDirs(L, dirs);
        pushConfig(L, config);
        pushDepInfos(L, depInfos);

        const cwd = getcwd();
        chdir(dirs.build);
        scope(exit)
            chdir(cwd);

        if (lua_pcall(L, /* nargs = */ 3, /* nresults = */ 0, 0) != LUA_OK)
        {
            throw new Exception("Cannot build recipe: " ~ luaPop!string(L));
        }
    }

    @property bool canStage() const @safe
    {
        return !_stageFalse;
    }

    void stage(string src, string dest) @system
    in (isAbsolute(src) && isAbsolute(dest))
    {
        import dopamine.util : installRecurse;
        import std.string : startsWith;

        assert(buildNormalizedPath(src).startsWith(_rootDir));

        lua_getglobal(L, "stage");
        if (lua_type(L, -1) == LUA_TFUNCTION)
        {
            luaPush(L, src);
            luaPush(L, dest);

            const cwd = getcwd();
            chdir(src);
            scope(exit)
                chdir(cwd);

            if (lua_pcall(L, 2, 0, 0) != LUA_OK)
            {
                throw new Exception("Cannot stage recipe: " ~ luaPop!string(L));
            }
        }
        else
        {
            installRecurse(src, dest);
        }
    }

    private bool hasFunction(string funcname) const @safe
    {
        import std.algorithm : canFind;

        return _funcs.canFind(funcname);
    }
}

private:

/// Read a dependency table from top of the stack.
/// The table is left on the stack after return
DepSpec[] readDependencies(lua_State* L) @trusted
{
    const typ = lua_type(L, -1);
    if (typ == LUA_TNIL)
        return null;

    enforce(typ == LUA_TTABLE, "invalid dependencies return type");

    DepSpec[] res;

    // first key
    lua_pushnil(L);

    while (lua_next(L, -2))
    {
        scope (failure)
            lua_pop(L, 1);

        DepSpec dep;
        dep.name = enforce(luaTo!string(L, -2, null), // probably a number key (dependencies specified as array)
            // relying on lua_tostring for having a correct string inference
            format("Invalid dependency name: %s", lua_tostring(L, -2)));

        const vtyp = lua_type(L, -1);
        switch (vtyp)
        {
        case LUA_TSTRING:
            dep.spec = VersionSpec(luaTo!string(L, -1));
            break;
        case LUA_TTABLE:
            {
                const ver = luaGetTable!string(L, -1, "version", null);
                dep.spec = VersionSpec(enforce(ver,
                        format("'version' not specified for '%s' dependency", dep.name)));
                dep.dub = luaGetTable!bool(L, -1, "dub", false);
                break;
            }
        default:
            throw new Exception(format("Invalid dependency specification for '%s'", dep.name));
        }
        res ~= dep;

        lua_pop(L, 1);
    }
    return res;
}

void pushBuildDirs(lua_State* L, BuildDirs dirs) @trusted
{
    lua_createtable(L, 0, 4);
    const ind = lua_gettop(L);
    luaSetTable(L, ind, "root", dirs.root);
    luaSetTable(L, ind, "src", dirs.src);
    luaSetTable(L, ind, "build", dirs.build);
    luaSetTable(L, ind, "install", dirs.install);
}

void pushConfig(lua_State* L, BuildConfig config) @trusted
{
    lua_createtable(L, 0, 4);
    const ind = lua_gettop(L);

    lua_pushliteral(L, "profile");
    luaPushProfile(L, config.profile);
    lua_settable(L, ind);

    // TODO options
}

void pushDepInfos(lua_State* L, DepInfo[string] depInfos) @trusted
{
    if (!depInfos)
    {
        lua_pushnil(L);
        return;
    }

    lua_createtable(L, 0, cast(int) depInfos.length);
    const depInfosInd = lua_gettop(L);
    foreach (k, di; depInfos)
    {
        lua_pushlstring(L, k.ptr, k.length);

        lua_createtable(L, 0, 2);
        luaSetTable(L, -1, "install_dir", di.installDir);
        luaSetTable(L, -1, "version", di.ver.toString());

        lua_settable(L, depInfosInd);
    }
}
