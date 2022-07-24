module dopamine.recipe;

import dopamine.build_id;
import dopamine.dep.spec;
import dopamine.lua.lib;
import dopamine.lua.profile;
import dopamine.lua.util;
import dopamine.profile;
import dopamine.semver;

import dopamine.c.lua;

import std.digest;
import std.exception;
import std.json;
import std.string;
import std.stdio;
import std.variant;

/// A recipe dependency specification
struct DepSpec
{
    string name;
    VersionSpec spec;
}

/// Directories passed to the `build` recipe function
struct BuildDirs
{
    string root;
    string src;
    string install;

    invariant
    {
        import std.path : isAbsolute;

        assert(root.isAbsolute);
        assert(src.isAbsolute);
        assert(install.isAbsolute);
    }
}

/// The build configuration
struct BuildConfig
{
    /// the build profile
    const(Profile) profile;

    // TODO: options

    void feedDigest(D)(ref D digest) const
    {
        profile.feedDigest(digest);
    }
}

struct DepInfo
{
    string installDir;
}

enum RecipeType
{
    pack,
    light,
}

struct Recipe
{
    import std.path : isAbsolute;

    // Implementation note:
    //  - the Recipe struct acts as a reference counter to the payload (d)
    //  - the payload carries a Lua state that is unique to the recipe (no state sharing between recipes)
    //  - in case of a light recipe, the lua stack stays clean between function calls
    //  - in case of a package recipe, the lua stack keeps the recipe table (self) on top between function calls (and only this table)

    private RecipePayload d;

    private this(RecipePayload d) @safe
    in (d !is null && d.rc == 1)
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

    invariant
    {
        if (d is null)
            return;

        auto L = cast(lua_State*) d.L; // const cast
        assert(lua_gettop(L) == 0, "Recipe do not have proper stack");
    }

    bool opCast(T : bool)() const @safe
    {
        return d !is null;
    }

    @property string filename() const @safe
    {
        return d.filename;
    }

    @property RecipeType type() const @safe
    {
        return d.type;
    }

    @property bool isLight() const @safe
    {
        return d.type == RecipeType.light;
    }

    @property bool isPackage() const @safe
    {
        return d.type == RecipeType.pack;
    }

    bool hasFunction(string fname) const @safe
    {
        import std.algorithm : canFind;

        return d.funcs.canFind(fname);
    }

    @property bool stageFalse() const @safe
    {
        return d.stageFalse;
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

    @property bool hasDependencies() const @safe
    {
        return hasFunction("dependencies") || d.dependencies.length != 0;
    }

    @property const(DepSpec)[] dependencies(const(Profile) profile) @system
    {
        if (!hasFunction("dependencies"))
            return d.dependencies;

        auto L = d.L;

        // If this is a light recipe, the dependency function only take a profile argument.
        // Otherwise it take 'self' in addition as first argument
        // It will return a dependency table.

        lua_getglobal(L, "dependencies");

        const nargs = 1;
        const funcPos = 1;

        assert(lua_type(L, funcPos) == LUA_TFUNCTION);

        luaPushProfile(L, profile);

        if (lua_pcall(L, nargs, /* nresults = */ 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot get dependencies: " ~ luaPop!string(L));
        }

        scope (success)
            lua_pop(L, 1);

        return readDependencies(L);
    }

    @property string revision() @system
    in (isPackage, "Light recipes do not have revision")
    {
        if (d.revision)
            return d.revision;

        auto L = d.L;

        lua_getglobal(L, "revision");

        if (d.filename && lua_type(L, -1) == LUA_TNIL)
        {
            lua_pop(L, 1);
            return sha1RevisionFromFile(d.filename);
        }

        enforce(lua_type(L, -1) == LUA_TFUNCTION,
            "Wrong revision field: expected a function or nil");

        if (lua_pcall(L, /* nargs = */ 0, /* nresults = */ 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot get recipe revision: " ~ luaPop!string(L));
        }

        d.revision = luaTo!string(L, -1);
        return d.revision;
    }

    string[] include() @system
    {
        if (d.included)
            return d.included;

        auto L = d.L;

        lua_getglobal(L, "include");
        if (lua_type(L, -1) == LUA_TNIL)
        {
            lua_pop(L, 1);
            return null;
        }

        assert(lua_type(L, -1) == LUA_TFUNCTION,
            "function expected for 'include'"
        );

        if (lua_pcall(L, 0, 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot get files included with recipe: " ~ luaPop!string(L));
        }

        string[] result = luaReadStringArray(L, -1);
        lua_pop(L, 1);
        return result;
    }

    /// Returns: whether the source is included with the package
    @property bool inTreeSrc() const @safe
    {
        return d.inTreeSrc.length > 0;
    }

    /// Execute the 'source' function if the recipe has one and return its result.
    /// Otherwise return the 'source' string variable (default to "." if undefined)
    string source() @system
    in (isPackage, "Light recipes do not have source")
    {
        if (d.inTreeSrc)
            return d.inTreeSrc;

        auto L = d.L;

        lua_getglobal(L, "source");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a source function");

        if (lua_pcall(L, /* nargs = */ 0, /* nresults = */ 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot get source: " ~ luaPop!string(L));
        }

        return L.luaPop!string();
    }

    private void pushBuildDirs(lua_State* L, BuildDirs dirs) @trusted
    {
        lua_createtable(L, 0, 2);
        const ind = lua_gettop(L);
        luaSetTable(L, ind, "root", dirs.root);
        luaSetTable(L, ind, "src", dirs.src);
        luaSetTable(L, ind, "install", dirs.install);
    }

    private void pushConfig(lua_State* L, BuildConfig config) @trusted
    {
        lua_createtable(L, 0, 4);
        const ind = lua_gettop(L);

        lua_pushliteral(L, "profile");
        luaPushProfile(L, config.profile);
        lua_settable(L, ind);

        // TODO options
    }

    private void pushDepInfos(lua_State* L, DepInfo[string] depInfos) @trusted
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

            lua_createtable(L, 0, 1);
            luaSetTable(L, -1, "install_dir", di.installDir);

            lua_settable(L, depInfosInd);
        }
    }

    /// Execute the `build` function of this recipe
    void build(BuildDirs dirs, BuildConfig config, DepInfo[string] depInfos = null) @system
    in (isPackage, "Light recipes do not build")
    {
        auto L = d.L;

        lua_getglobal(L, "build");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a build function");

        pushBuildDirs(L, dirs);
        pushConfig(L, config);
        pushDepInfos(L, depInfos);

        if (lua_pcall(L, /* nargs = */ 3, /* nresults = */ 0, 0) != LUA_OK)
        {
            throw new Exception("Cannot build recipe: " ~ luaPop!string(L));
        }
    }

    /// Execute the `stage` function of this recipe, which MUST be defined
    void stage(string dest) @system
    in (isPackage, "Light recipes do not stage")
    in (hasFunction("stage"))
    in (isAbsolute(dest))
    {
        auto L = d.L;

        lua_getglobal(L, "stage");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a stage function");

        luaPush(L, dest);

        if (lua_pcall(L, 1, 0, 0) != LUA_OK)
        {
            throw new Exception("Cannot stage recipe: " ~ luaPop!string(L));
        }
    }

    /// Execute the `post_stage` function of this recipe, which MUST be defined
    void postStage() @system
    in (isPackage, "Light recipes do not stage")
    in (hasFunction("post_stage"))
    {
        auto L = d.L;

        lua_getglobal(L, "post_stage");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a post_stage function");

        if (lua_pcall(L, 0, 0, 0) != LUA_OK)
        {
            throw new Exception("Cannot post-stage recipe: " ~ luaPop!string(L));
        }
    }

    static Recipe parseFile(string path, string revision = null) @system
    {
        auto d = RecipePayload.parse(path, revision);
        return Recipe(d);
    }

    static Recipe mock(string name, Semver ver, DepSpec[] deps, Lang[] langs, string revision) @trusted
    {
        import dopamine.c.lua : lua_createtable;

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
    RecipeType type;
    string name;
    string description;
    Semver ver;
    string license;
    string copyright;
    Lang[] langs;
    string[] included;

    DepSpec[] dependencies;
    string[] funcs;
    string inTreeSrc;
    bool stageFalse;

    string filename;
    string revision;

    lua_State* L;
    int rc;

    this() @trusted
    {
        L = luaL_newstate();
        luaL_openlibs(L);

        // setting the payload to ["payload"] key in the registry
        lua_pushlightuserdata(L, cast(void*) this);
        lua_setfield(L, LUA_REGISTRYINDEX, "payload");

        luaLoadDopLib(L);

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

    private static RecipePayload parse(string filename, string revision) @system
    in (filename !is null)
    {
        import std.path : isAbsolute;

        auto d = new RecipePayload();
        auto L = d.L;

        assert(lua_gettop(L) == 0);

        if (luaL_dofile(L, filename.toStringz))
        {
            throw new Exception("cannot parse package recipe file: " ~ luaPop!string(L));
        }

        d.filename = filename;

        enforce(
            lua_gettop(L) == 0,
            "Recipes should not return anything"
        );

        // start with the build function because it determines whether
        // it is a light recipe or package recipe
        {
            lua_getglobal(L, "build");
            scope (exit)
                lua_pop(L, 1);

            switch (lua_type(L, -1))
            {
            case LUA_TFUNCTION:
                d.funcs ~= "build";
                d.type = RecipeType.pack;
                break;
            case LUA_TNIL:
                d.type = RecipeType.light;
                break;
            default:
                throw new Exception("Invalid 'build' field: expected a function");
            }
        }
        // langs and dependencies are needed regardless of recipe type
        {
            lua_getglobal(L, "langs");
            scope (exit)
                lua_pop(L, 1);

            d.langs = luaReadStringArray(L, -1).strToLangs();
        }
        {
            lua_getglobal(L, "dependencies");
            scope (exit)
                lua_pop(L, 1);

            switch (lua_type(L, -1))
            {
            case LUA_TFUNCTION:
                d.funcs ~= "dependencies";
                break;
            case LUA_TTABLE:
                d.dependencies = readDependencies(L);
                break;
            case LUA_TNIL:
                enforce(
                    d.type == RecipeType.pack,
                    "Light recipe without dependency"
                );
                break;
            default:
                throw new Exception("invalid dependencies specification");
            }
        }

        if (d.type == RecipeType.pack)
        {
            d.name = enforce(
                luaGetGlobal!string(L, "name", null),
                "The name field is mandatory in the recipe"
            );
            const verStr = enforce(
                luaGetGlobal!string(L, "version", null),
                "The version field is mandatory in the recipe"
            );
            d.ver = verStr ? Semver(verStr) : Semver.init;
            d.description = luaGetGlobal!string(L, "description", null);
            d.license = luaGetGlobal!string(L, "license", null);
            d.copyright = luaGetGlobal!string(L, "copyright", null);

            if (revision)
            {
                d.revision = revision;
            }
            else
            {
                lua_getglobal(L, "revision");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TFUNCTION:
                    d.funcs ~= "revision";
                    // will be called from Recipe.revision
                    break;
                case LUA_TNIL:
                    // revision will be lazily computed from the file content in Recipe.revision
                    break;
                case LUA_TSTRING:
                    d.revision = luaToString(L, -1);
                    break;
                default:
                    throw new Exception("Invalid revision specification");
                }
            }

            {
                lua_getglobal(L, "include");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TTABLE:
                    d.included = luaReadStringArray(L, -1);
                    break;
                case LUA_TSTRING:
                    d.included = [luaTo!string(L, -1)];
                    break;
                case LUA_TFUNCTION:
                    d.funcs ~= "include";
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
                    d.inTreeSrc = luaTo!string(L, -1);
                    enforce(!isAbsolute(d.inTreeSrc),
                        "constant source must be relative to package file");
                    break;
                case LUA_TFUNCTION:
                    d.funcs ~= "source";
                    break;
                case LUA_TNIL:
                    d.inTreeSrc = ".";
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
                    d.funcs ~= "stage";
                    break;
                case LUA_TBOOLEAN:
                    import dopamine.log : logWarningH;

                    if (!luaTo!bool(L, -1))
                        d.stageFalse = true;
                    else
                        logWarningH("%s: `stage = true` has no effect.", filename);
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
                    d.funcs ~= "post_stage";
                    break;
                case LUA_TNIL:
                    break;
                default:
                    throw new Exception("Invalid 'post_stage' field: expected a function");
                }
            }
        }

        assert(lua_gettop(L) == 0, "Lua stack not clean");

        return d;
    }
}

private:

string sha1RevisionFromContent(const(char)[] luaContent) @safe
{
    import std.digest.sha : sha1Of;
    import std.digest : toHexString, LetterCase;

    const hash = sha1Of(luaContent);
    return toHexString!(LetterCase.lower)(hash).idup;
}

string sha1RevisionFromFile(string filename) @safe
{
    import std.file : read;

    return sha1RevisionFromContent(cast(const(char)[]) read(filename));
}

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
