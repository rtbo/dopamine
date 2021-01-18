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
import std.variant;

enum BuildOptionType
{
    boolean,
    str,
    choice,
    number,
}

alias BuildOptionVal = Algebraic!(string, bool, int);

struct BuildOptionDef
{
    BuildOptionType type;
    string[] choices;
    BuildOptionVal def;
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

    @property const(Dependency)[] dependencies(const(Profile) profile)
    {
        if (!d.depFunc)
            return d.dependencies;

        auto L = d.L;

        // the dependencies func takes a profile as argument
        // and return dependency table
        lua_getglobal(L, "dependencies");
        assert(lua_type(L, -1) == LUA_TFUNCTION);

        luaPushProfile(L, profile);

        // 1 argument, 1 result
        if (lua_pcall(L, 1, 1, 0) != LUA_OK)
        {
            throw new Exception("cannot get dependencies: " ~ luaTo!string(L, -1));
        }

        scope (success)
            lua_pop(L, 1);

        return readDependencies(L);
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

    /// Returns: whether the source is included with the package
    @property bool inTreeSrc() const
    {
        return d.inTreeSrc.length > 0;
    }

    string source()
    {
        if (d.inTreeSrc)
            return d.inTreeSrc;

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

    string build(Profile profile, string srcDir, string buildDir, string installDir)
    {
        auto L = d.L;

        lua_getglobal(L, "build");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a build function");

        lua_createtable(L, 0, 3);
        const paramsInd = lua_gettop(L);

        lua_pushliteral(L, "profile");
        luaPushProfile(L, profile);
        lua_settable(L, paramsInd);

        luaSetTable(L, paramsInd, "src_dir", srcDir);
        luaSetTable(L, paramsInd, "build_dir", buildDir);
        luaSetTable(L, paramsInd, "install_dir", installDir);

        // 1 argument, 1 result
        if (lua_pcall(L, 1, 1, 0) != LUA_OK)
        {
            throw new Exception("cannot build recipe: " ~ luaTo!string(L, -1));
        }

        scope (success)
            lua_pop(L, 1);

        string result = installDir;
        switch (lua_type(L, -1))
        {
        case LUA_TSTRING:
            result = luaTo!string(L, -1);
            break;
        case LUA_TNIL:
            break;
        default:
            throw new Exception("invalid return from build");
        }
        return result;
    }

    static Recipe parseFile(string path, string revision = null)
    {
        import std.file : read;

        auto d = RecipePayload.parse(null, path, revision);
        return Recipe(d);
    }

    static Recipe parseString(const(char)[] content, string revision = null)
    {
        auto d = RecipePayload.parse(content, null, revision);
        return Recipe(d);
    }

    static Recipe mock(string name, Semver ver, Dependency[] deps, Lang[] langs, string revision) @trusted
    {
        auto d = new RecipePayload();
        d.name = name;
        d.ver = ver;
        d.dependencies = deps;
        d.langs = langs;
        d.revision = revision;
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
    bool depFunc;

    string inTreeSrc;

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
    in((filename && !lua) || (!filename && lua))
    {
        import std.path : isAbsolute;

        auto d = new RecipePayload();
        auto L = d.L;

        if (filename && luaL_dofile(L, filename.toStringz))
        {
            throw new Exception("cannot parse package recipe file: " ~ fromStringz(lua_tostring(L,
                    -1)).idup);
        }
        else if (luaL_dostring(L, lua.toStringz))
        {
            throw new Exception("cannot parse package recipe file: " ~ fromStringz(lua_tostring(L,
                    -1)).idup);

        }

        d.name = luaGetGlobal!string(L, "name", null);
        d.ver = Semver(luaGetGlobal!string(L, "version"));
        d.description = luaGetGlobal!string(L, "description", null);
        d.license = luaGetGlobal!string(L, "license", null);
        d.copyright = luaGetGlobal!string(L, "copyright", null);
        d.langs = L.luaWithGlobal!("langs", () => luaReadStringArray(L, -1).strToLangs());

        L.luaWithGlobal!("dependencies", {
            switch (lua_type(L, -1))
            {
            case LUA_TFUNCTION:
                d.depFunc = true;
                break;
            case LUA_TTABLE:
                d.dependencies = readDependencies(L);
                break;
            case LUA_TNIL:
                break;
            default:
                throw new Exception("invalid dependencies specification");
            }
        });

        L.luaWithGlobal!("source", {
            switch (lua_type(L, -1))
            {
            case LUA_TSTRING:
                d.inTreeSrc = luaTo!string(L, -1);
                enforce(!isAbsolute(d.inTreeSrc),
                    "constant source must be relative to package file");
                break;
            case LUA_TFUNCTION:
                break;
            case LUA_TNIL:
                d.inTreeSrc = ".";
                break;
            default:
                throw new Exception("invalid source specification");
            }
        });

        d.filename = filename;

        if (revision)
        {
            d.revision = revision;
        }
        else
        {
            L.luaWithGlobal!("revision", {
                switch (lua_type(L, -1))
                {
                case LUA_TFUNCTION:
                    // will be called from Recipe.revision
                    break;
                case LUA_TNIL:
                    // revision must be computed from lua content
                    // we want to be as lazy as possible, because revision is
                    // generally needed only when package is uploaded.
                    // if filename is known, we defer revision to Recipe.revision
                    // if not known, we compute it now.

                    if (!d.filename)
                    {
                        assert(lua.length);
                        d.revision = sha1RevisionFromContent(lua);
                    }
                    break;
                default:
                    throw new Exception("Invalid revision specification");
                }
            });
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

    return sha1RevisionFromContent(cast(const(char)[]) read(filename));
}

/// Read a dependency table from top of the stack
Dependency[] readDependencies(lua_State* L)
{
    const typ = lua_type(L, -1);
    if (typ == LUA_TNIL)
        return null;

    enforce(typ == LUA_TTABLE, "invalid dependencies return type");

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
                const aa = luaReadStringDict(L, -1);
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
