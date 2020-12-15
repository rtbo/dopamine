module dopamine.recipe;

import dopamine.build;
import dopamine.source;

import bindbc.lua;

import std.exception;
import std.json;
import std.string;
import std.stdio;

@safe:

class Recipe
{
    private
    {
        string _name;
        string _description;
        string _ver;
        string _license;
        string _copyright;
        string[] _langs;

        Source _repo;
        Source _source;
        BuildSystem _build;
    }

    @property string name() const
    {
        return _name;
    }

    @property string description() const
    {
        return _description;
    }

    @property string ver() const
    {
        return _ver;
    }

    @property string license() const
    {
        return _license;
    }

    @property string copyright() const
    {
        return _copyright;
    }

    @property const(string)[] langs() const
    {
        return _langs;
    }

    @property const(Source) repo() const
    {
        return _repo;
    }

    @property const(Source) source() const
    {
        return _source;
    }

    @property bool outOfTree() const
    {
        return _repo !is _source;
    }

    @property const(BuildSystem) build() const
    {
        return _build;
    }
}

const(Recipe) recipeParseJson(const ref JSONValue json)
{
    auto r = new Recipe;

    r._name = json["name"].str;
    r._ver = json["version"].str;
    r._description = json["description"].str;
    r._license = json["license"].str;
    r._copyright = json["copyright"].str;
    r._langs = jsonArray(json["langs"].arrayNoRef);

    r._repo = source(jsonObject(json["repo"].objectNoRef));

    if (!json["source"].isNull)
    {
        r._source = source(jsonObject(json["source"].objectNoRef));
    }
    else
    {
        r._source = r._repo;
    }

    r._build = buildSystem(jsonObject(json["build"].objectNoRef));

    return r;
}

JSONValue recipeToJson(const(Recipe) recipe)
{
    JSONValue json;
    if (recipe.name.length)
        json["name"] = recipe.name;
    if (recipe.ver.length)
        json["version"] = recipe.ver;
    if (recipe.description.length)
        json["description"] = recipe.description;
    if (recipe.license.length)
        json["license"] = recipe.license;
    if (recipe.copyright.length)
        json["copyright"] = recipe.copyright;
    if (recipe.langs.length)
        json["langs"] = recipe.langs;
    if (recipe.repo)
        json["repo"] = recipe.repo.toJson();
    if (recipe.source && !recipe.outOfTree)
    {
        json["source"] = recipe.source.toJson();
    }
    if (recipe.build)
        json["build"] = recipe.build.toJson();

    return json;
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

const(Recipe) recipeParseFile(string path) @trusted
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

    r._name = enforce(globalStringVar(L, "name"), "name field is mandatory");
    r._ver = enforce(globalStringVar(L, "version"), "version field is mandatory");
    r._description = globalStringVar(L, "description");
    r._license = globalStringVar(L, "license");
    r._copyright = globalStringVar(L, "copyright");
    r._langs = globalArrayTableVar(L, "langs");

    r._repo = source(globalDictTableVar(L, "repo"));
    if (globalIsNil(L, "source") || globalEqual(L, "repo", "source"))
    {
        r._source = r._repo;
    }
    else
    {
        r._source = source(globalDictTableVar(L, "source"));
    }
    r._build = buildSystem(globalDictTableVar(L, "build"));

    assert(lua_gettop(L) == 0, "Lua stack not clean");

    lua_close(L);

    return r;

}

private:

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

    case "archive":
        {
            auto url = enforce("url" in aa, "url is mandator for Archive source");
            auto md5 = "md5" in aa;
            auto sha1 = "sha1" in aa;
            auto sha256 = "sha256" in aa;

            enforce(md5 || sha1 || sha256,
                    "you must specify at least one of md5, sha1 or sha256 checksums for Archive");

            Checksum checksum;
            if (sha256)
            {
                checksum.type = Checksum.Type.sha256;
                checksum.checksum = *sha256;
            }
            else if (sha1)
            {
                checksum.type = Checksum.Type.sha1;
                checksum.checksum = *sha1;
            }
            else if (md5)
            {
                checksum.type = Checksum.Type.md5;
                checksum.checksum = *md5;
            }

            return new ArchiveSource(*url, checksum);
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
    case "cmake":
        return new CMakeBuildSystem();
    case "meson":
        return new MesonBuildSystem();
    default:
        break;
    }

    return null;
}

string[string] jsonObject(in JSONValue[string] obj)
{
    string[string] aa;
    foreach (k, v; obj)
    {
        aa[k] = v.str;
    }
    return aa;
}

string[] jsonArray(in JSONValue[] arr)
{
    import std.algorithm : map;
    import std.array : array;

    return arr.map!(jv => jv.str).array;
}

int dopModuleLoader(lua_State* L) nothrow @trusted
{
    import core.stdc.stdio : fprintf, stderr;

    auto dopMod = import("dop.lua");

    const res = luaL_dostring(L, dopMod.ptr);
    if (res != LUA_OK)
    {
        fprintf(stderr, "Error during 'dop.lua' execution: %s\n", lua_tostring(L, -1));
        lua_pop(L, 1);
        return 0;
    }

    return 1;
}

string globalStringVar(lua_State* L, string varName, string def = null) @trusted
{
    lua_getglobal(L, toStringz(varName));

    scope (success)
        lua_pop(L, 1);

    auto res = getString(L, -1);

    return res ? res : def;
}

bool globalBoolVar(lua_State* L, string varName, bool def = false) @trusted
{
    lua_getglobal(L, toStringz(varName));

    scope (success)
        lua_pop(L, 1);

    if (lua_type(L, -1) != LUA_TBOOLEAN)
        return def;

    return lua_toboolean(L, -1) != 0;
}

string[string] globalDictTableVar(lua_State* L, string varName) @trusted
{
    lua_getglobal(L, toStringz(varName));
    scope (success)
        lua_pop(L, 1);
    return getStringDictTable(L, -1);
}

string[] globalArrayTableVar(lua_State* L, string varName) @trusted
{
    lua_getglobal(L, toStringz(varName));
    scope (success)
        lua_pop(L, 1);
    return getStringArrayTable(L, -1);
}

bool globalIsNil(lua_State* L, string var) @trusted
{
    lua_getglobal(L, toStringz(var));
    scope (success)
        lua_pop(L, 1);
    return lua_isnil(L, -1);
}

bool globalEqual(lua_State* L, string var1, string var2) @trusted
{
    lua_getglobal(L, toStringz(var1));
    lua_getglobal(L, toStringz(var2));
    scope (success)
        lua_pop(L, 2);
    return lua_equal(L, -2, -1) == 1;
}

/// Get a string at index ind in the stack.
string getString(lua_State* L, int ind) @trusted
{
    if (lua_type(L, ind) != LUA_TSTRING)
        return null;

    size_t len;
    const ptr = lua_tolstring(L, ind, &len);
    return ptr[0 .. len].idup;
}

/// Get all strings in a table at stack index [ind] who have string keys.
string[string] getStringDictTable(lua_State* L, int ind) @trusted
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
string[] getStringArrayTable(lua_State* L, int ind) @trusted
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

void printStack(lua_State* L) @trusted
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

void printTable(lua_State* L, int ind) @trusted
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
