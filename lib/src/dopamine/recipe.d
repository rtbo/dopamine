module dopamine.recipe;

import dopamine.lua.lib;
import dopamine.lua.profile;
import dopamine.lua.util;
import dopamine.dependency;
import dopamine.profile;
import dopamine.semver;

import bindbc.lua;

import std.exception;
import std.json;
import std.string;
import std.stdio;

/// Information relative to an installed dependency
struct DepInfo
{
    Semver ver;
    string installDir;
}

struct Recipe
{
    private RecipePayload d;

    private this(RecipePayload d)
    in(d !is null && d.rc == 1)
    {
        this.d = d;
    }

    this(this) @safe
    {
        if (d !is null)
            d.incr();
    }

    ~this() @safe
    {
        if (d !is null)
            d.decr();
    }

    bool opCast(T : bool)() const
    {
        return d !is null;
    }

    @property string name() const @safe
    {
        return d.name;
    }

    @property string description() const @safe
    {
        return d.description;
    }

    @property Semver ver() const @safe
    {
        return d.ver;
    }

    @property string license() const @safe
    {
        return d.license;
    }

    @property string copyright() const @safe
    {
        return d.copyright;
    }

    @property const(Lang)[] langs() const @safe
    {
        return d.langs;
    }

    @property const(Dependency)[] dependencies() const @safe
    {
        return d.dependencies;
    }

    @property string filename() const @safe
    {
        return d.filename;
    }

    @property string revision()
    {
        if (d.revision)
            return d.revision;

        auto L = d.L;

        lua_getglobal(L, "revision");
        scope (success)
            lua_pop(L, 1);

        if (d.filename && lua_type(L, -1) == LUA_TNIL)
        {
            return sha1RevisionFromFile(d.filename);
        }

        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a recipe function");

        // no argument, 1 result
        if (lua_pcall(L, 0, 1, 0) != LUA_OK)
        {
            throw new Exception("cannot get revision: " ~ luaTo!string(L, -1));
        }

        return luaTo!string(L, -1);
    }

    string source()
    {
        auto L = d.L;

        lua_getglobal(L, "source");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a source function");

        // no argument, 1 result
        if (lua_pcall(L, 0, 1, 0) != LUA_OK)
        {
            throw new Exception("cannot get source: " ~ luaTo!string(L, -1));
        }

        return L.luaPop!string();
    }

    void build(Profile profile, string srcdir, string builddir, string installdir)
    {
        auto L = d.L;

        lua_getglobal(L, "build");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a build function");

        lua_createtable(L, 0, 3);
        const paramsInd = lua_gettop(L);

        lua_pushliteral(L, "profile");
        luaPushProfile(L, profile);
        lua_settable(L, paramsInd);

        luaSetTable(L, paramsInd, "src_dir", srcdir);
        luaSetTable(L, paramsInd, "build_dir", builddir);
        luaSetTable(L, paramsInd, "install_dir", installdir);

        // 1 argument, no result
        if (lua_pcall(L, 1, 0, 0) != LUA_OK)
        {
            throw new Exception("cannot build recipe: " ~ luaTo!string(L, -1));
        }
    }

    static Recipe parseFile(string path, string revision = null)
    {
        import std.file : read;

        const lua = cast(const(char)[]) read(path);
        auto d = RecipePayload.parse(lua, path, revision);
        return Recipe(d);
    }

    static Recipe parseString(const(char)[] content, string revision = null)
    {
        auto d = RecipePayload.parse(content, null, revision);
        return Recipe(d);
    }

    static Recipe mock(string name, Semver ver, Dependency[] deps, Lang[] langs) @trusted
    {
        auto d = new RecipePayload();
        d.name = name;
        d.ver = ver;
        d.dependencies = deps;
        d.langs = langs;
        return Recipe(d);
    }
}

package class RecipePayload
{
    string name;
    string description;
    Semver ver;
    string license;
    string copyright;
    Lang[] langs;

    Dependency[] dependencies;

    string filename;
    string revision;

    lua_State* L;
    int rc;

    this()
    {
        L = luaL_newstate();
        luaL_openlibs(L);

        // setting the payload to ["recipe"] key in the registry
        lua_pushlightuserdata(L, cast(void*) this);
        lua_setfield(L, LUA_REGISTRYINDEX, "recipe");

        luaPreloadDopLib(L);

        rc = 1;
    }

    void incr() @safe
    {
        rc++;
    }

    void decr() @trusted
    {
        rc--;
        if (!rc)
        {
            lua_close(L);
            L = null;
        }
    }

    private static RecipePayload parse(const(char)[] lua, string filename, string revision)
    {
        auto d = new RecipePayload();
        auto L = d.L;

        if (luaL_dostring(L, lua.toStringz))
        {
            throw new Exception("cannot parse package recipe file: " ~ fromStringz(lua_tostring(L,
                    -1)).idup);
        }

        d.name = luaGetGlobal!string(L, "name", null);
        d.ver = Semver(luaGetGlobal!string(L, "version"));
        d.description = luaGetGlobal!string(L, "description", null);
        d.license = luaGetGlobal!string(L, "license", null);
        d.copyright = luaGetGlobal!string(L, "copyright", null);
        d.langs = globalArrayTableVar(L, "langs").strToLangs();

        d.dependencies = readDependencies(L);

        d.filename = filename;

        if (revision)
        {
            d.revision = revision;
        }
        else
        {
            lua_getglobal(L, "revision");
            switch (lua_type(L, -1))
            {
            case LUA_TFUNCTION:
                // will be called from Recipe.revision
                lua_pop(L, 1);
                break;
            case LUA_TNIL:
                {
                    // revision must be computed from lua content
                    // we want to be as lazy as possible, because revision is
                    // generally needed only when package is uploaded.
                    // if filename is known, we defer revision to Recipe.revision
                    // if not known, we compute it now.

                    if (!d.filename)
                    {
                        d.revision = sha1RevisionFromContent(lua);
                    }
                    lua_pop(L, 1);
                    break;
                }
            default:
                throw new Exception("Invalid revision specified");
            }
        }

        assert(lua_gettop(L) == 0, "Lua stack not clean");

        return d;
    }
}

private:

string sha1RevisionFromContent(const(char)[] luaContent)
{
    import std.digest.sha : sha1Of;
    import std.digest : toHexString, LetterCase;

    const hash = sha1Of(luaContent);
    return toHexString!(LetterCase.lower)(hash).idup;
}

string sha1RevisionFromFile(string filename)
{
    import std.file : read;

    return sha1RevisionFromContent(cast(const(char)[])read(filename));
}

Dependency[] readDependencies(lua_State* L)
{
    lua_getglobal(L, "dependencies");

    scope (success)
        lua_pop(L, 1);

    const typ = lua_type(L, -1);
    if (typ == LUA_TNIL)
        return null;

    enforce(typ == LUA_TTABLE, "Invalid dependencies declaration");

    Dependency[] res;

    // first key
    lua_pushnil(L);

    while (lua_next(L, -2))
    {
        scope (failure)
            lua_pop(L, 1);

        Dependency dep;
        dep.name = enforce(luaTo!string(L, -2, null),
                // probably a number key (dependencies specified as array)
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
                const aa = getStringDictTable(L, -1);
                dep.spec = VersionSpec(enforce(aa["version"],
                        format("'version' not specified for '%s' dependency", dep.name)));
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
