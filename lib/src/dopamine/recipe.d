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

struct BuildDirs
{
    string src;
    string config;
    string build;
    string install;

    PackDirs toPack(string dest = null) const
    {
        return PackDirs(src, config, build, install, dest ? dest : install);
    }

    invariant
    {
        import std.path : isAbsolute;

        assert(src.isAbsolute);
        assert(config.isAbsolute);
        assert(build.isAbsolute);
        assert(install.isAbsolute);
    }
}

struct PackDirs
{
    string src;
    string config;
    string build;
    string install;
    string dest;

    invariant
    {
        import std.path : isAbsolute;

        assert(src.isAbsolute);
        assert(config.isAbsolute);
        assert(build.isAbsolute);
        assert(install.isAbsolute);
        assert(dest.isAbsolute);
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
    // Implementation note:
    //  - the Recipe struct acts as a reference counter to the payload (d)
    //  - the payload carries a Lua state that is unique to the recipe (no state sharing between recipes)
    //  - in case of a light recipe, the lua stack stays clean between function calls
    //  - in case of a package recipe, the lua stack keeps the recipe table (self) on top between function calls (and only this table)

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

    invariant
    {
        if (d is null)
            return;

        auto L = cast(lua_State*) d.L; // const cast
        final switch (d.type)
        {
        case RecipeType.light:
            assert(lua_gettop(L) == 0, "Light recipe do not have proper stack");
            break;
        case RecipeType.pack:
            assert(lua_gettop(L) == 1, "Package recipe do not have proper stack");
            assert(lua_type(L, 1) == LUA_TTABLE, "Package recipe has corrupted stack");
            break;
        }
    }

    bool opCast(T : bool)() const
    {
        return d !is null;
    }

    @property RecipeType type() const
    {
        return d.type;
    }

    @property bool isLight() const
    {
        return d.type == RecipeType.light;
    }

    @property bool isPackage() const
    {
        return d.type == RecipeType.pack;
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
        return d.depFunc || d.dependencies.length != 0;
    }

    @property const(Dependency)[] dependencies(const(Profile) profile)
    {
        if (!d.depFunc)
            return d.dependencies;

        auto L = d.L;

        // If this is a light recipe, the dependency function only take a profile argument.
        // Otherwise it take 'self' in addition as first argument
        // It will return a dependency table.

        final switch (d.type)
        {
        case RecipeType.light:
            lua_getglobal(L, "dependencies");
            break;
        case RecipeType.pack:
            lua_getfield(L, 1, "dependencies");
            lua_pushvalue(L, 1); // push self on top
            break;
        }

        // cannot use isLight or isPackage here because it triggers invariant check
        const nargs = d.type == RecipeType.light ? 1 : 2;
        const funcPos = d.type == RecipeType.light ? 1 : 2;

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

    @property string filename() const @safe
    {
        return d.filename;
    }

    @property string revision()
    in(isPackage, "Light recipes do not have revision")
    {
        if (d.revision)
            return d.revision;

        auto L = d.L;

        lua_getfield(L, 1, "revision");

        if (d.filename && lua_type(L, -1) == LUA_TNIL)
        {
            lua_pop(L, 1);
            return sha1RevisionFromFile(d.filename);
        }

        enforce(lua_type(L, -1) == LUA_TFUNCTION,
                "Wrong revision field: expected a function or nil");

        lua_pushvalue(L, 1); // push self

        if (lua_pcall(L, /* nargs = */ 1, /* nresults = */ 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot get recipe revision: " ~ luaPop!string(L));
        }

        d.revision = luaTo!string(L, -1);
        return d.revision;
    }

    /// Returns: whether the source is included with the package
    @property bool inTreeSrc() const
    {
        return d.inTreeSrc.length > 0;
    }

    /// Execute the 'source' function if the recipe has one and return its result.
    /// Otherwise return the 'source' string variable (default to "." if undefined)
    string source()
    in(isPackage, "Light recipes do not have source")
    {
        if (d.inTreeSrc)
            return d.inTreeSrc;

        auto L = d.L;

        lua_getfield(L, 1, "source");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a source function");

        lua_pushvalue(L, 1); // push self

        if (lua_pcall(L, /* nargs = */ 1, /* nresults = */ 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot get source: " ~ luaPop!string(L));
        }

        return L.luaPop!string();
    }

    private void pushBuildDirs(lua_State* L, BuildDirs dirs)
    {
        lua_createtable(L, 0, 2);
        const ind = lua_gettop(L);
        luaSetTable(L, ind, "src", dirs.src);
        luaSetTable(L, ind, "config", dirs.config);
        luaSetTable(L, ind, "build", dirs.build);
        luaSetTable(L, ind, "install", dirs.install);
    }

    private void pushPackDirs(lua_State* L, PackDirs dirs)
    {
        lua_createtable(L, 0, 2);
        const ind = lua_gettop(L);
        luaSetTable(L, ind, "src", dirs.src);
        luaSetTable(L, ind, "config", dirs.config);
        luaSetTable(L, ind, "build", dirs.build);
        luaSetTable(L, ind, "install", dirs.install);
        luaSetTable(L, ind, "dest", dirs.dest);
    }

    private void pushConfig(lua_State* L, Profile profile)
    {
        lua_createtable(L, 0, 4);
        const ind = lua_gettop(L);

        lua_pushliteral(L, "profile");
        luaPushProfile(L, profile);
        lua_settable(L, ind);

        // TODO options

        const hash = profile.digestHash;
        const shortHash = hash[0 .. 10];
        luaSetTable(L, ind, "hash", hash);
        luaSetTable(L, ind, "short_hash", shortHash);
    }

    private void pushDepInfos(lua_State* L, DepInfo[string] depInfos)
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
    bool build(BuildDirs dirs, Profile profile, DepInfo[string] depInfos = null)
    in(isPackage, "Light recipes do not build")
    {
        auto L = d.L;

        lua_getfield(L, 1, "build");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a build function");

        lua_pushvalue(L, 1); // push self
        pushBuildDirs(L, dirs);
        pushConfig(L, profile);
        pushDepInfos(L, depInfos);

        if (lua_pcall(L, /* nargs = */ 4, /* nresults = */ 1, 0) != LUA_OK)
        {
            throw new Exception("Cannot build recipe: " ~ luaPop!string(L));
        }

        scope (exit)
            lua_pop(L, 1);

        bool result;
        switch (lua_type(L, -1))
        {
        case LUA_TBOOLEAN:
            result = luaTo!bool(L, -1);
            break;
        case LUA_TNIL:
            break;
        default:
            throw new Exception("invalid return from build");
        }
        return result;
    }

    @property bool hasPackFunc() const
    {
        return d.packFunc;
    }

    /// Execute the `package` function of this recipe
    void pack(PackDirs dirs, Profile profile, DepInfo[string] depInfos)
    in(isPackage, "Light recipes do not package")
    in(d.packFunc, "Recipe has no 'package' function")
    {
        auto L = d.L;

        lua_getfield(L, 1, "package");
        enforce(lua_type(L, -1) == LUA_TFUNCTION, "package recipe is missing a 'package' function");

        lua_pushvalue(L, 1); // push self
        pushPackDirs(L, dirs);
        pushConfig(L, profile);
        pushDepInfos(L, depInfos);

        if (lua_pcall(L, /* nargs = */ 4, /* nresults = */ 0, 0) != LUA_OK)
        {
            throw new Exception("Cannot create package: " ~ luaPop!string(L));
        }
    }

    /// Execute the `patch_install` function of this recipe
    void patchInstall(PackDirs dirs, Profile profile, DepInfo[string] depInfos)
    in(isPackage, "Light recipes do not patch")
    {
        auto L = d.L;

        lua_getfield(L, 1, "patch_install");

        switch (lua_type(L, -1))
        {
        case LUA_TFUNCTION:
            break;
        case LUA_TNIL:
            lua_pop(L, 1);
            return;
        default:
            const typ = luaL_typename(L, -1).fromStringz.idup;
            throw new Exception("invalid patch_install symbol: expected a function or nil, got " ~ typ);
        }

        lua_pushvalue(L, 1); // push self
        pushPackDirs(L, dirs);
        pushConfig(L, profile);
        pushDepInfos(L, depInfos);

        if (lua_pcall(L, /* nargs = */ 4, /* nresults = */ 0, 0) != LUA_OK)
        {
            throw new Exception("Cannot patch installation: " ~ luaPop!string(L));
        }
    }

    static Recipe parseFile(string path, string revision = null)
    {
        auto d = RecipePayload.parse(path, revision);
        return Recipe(d);
    }

    static Recipe mock(string name, Semver ver, Dependency[] deps, Lang[] langs, string revision) @trusted
    {
        import bindbc.lua : lua_createtable;

        auto d = new RecipePayload();
        d.name = name;
        d.ver = ver;
        d.dependencies = deps;
        d.langs = langs;
        d.revision = revision;

        // push empty recipe table to pass invariants
        lua_createtable(d.L, 0, 0);

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

    Dependency[] dependencies;
    bool depFunc;

    string inTreeSrc;

    bool packFunc;
    bool patchInstallFunc;

    string filename;
    string revision;

    lua_State* L;
    int rc;

    this()
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

    private static RecipePayload parse(string filename, string revision)
    in(filename !is null)
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

        if (lua_gettop(L) == 0)
        {
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
                    throw new Exception("light Recipe without dependency specification");
                default:
                    throw new Exception("invalid dependencies specification");
                }
            });

            d.langs = L.luaWithGlobal!("langs", () => luaReadStringArray(L, -1).strToLangs());
            d.type = RecipeType.light;
        }
        else if (lua_gettop(L) == 1)
        {
            enforce(lua_type(L, 1) == LUA_TTABLE, filename ~ " did not return a recipe table");

            d.name = enforce(luaGetTable!string(L, 1, "name", null),
                    "The name field is mandatory in the recipe");
            const verStr = enforce(luaGetTable!string(L, 1, "version", null),
                    "The version field is mandatory in the recipe");
            d.ver = verStr ? Semver(verStr) : Semver.init;
            d.description = luaGetTable!string(L, 1, "description", null);
            d.license = luaGetTable!string(L, 1, "license", null);
            d.copyright = luaGetTable!string(L, 1, "copyright", null);


            {
                lua_getfield(L, 1, "langs");
                scope (exit)
                    lua_pop(L, 1);

                d.langs = luaReadStringArray(L, -1).strToLangs();
            }
            {
                lua_getfield(L, 1, "dependencies");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TFUNCTION:
                    d.depFunc = true;
                    break;
                case LUA_TTABLE:
                    d.dependencies = readDependencies(L);
                    break;
                case LUA_TNIL:
                    break; // no dependency
                default:
                    throw new Exception("invalid dependencies specification");
                }
            }
            {
                lua_getfield(L, 1, "source");
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
                lua_getfield(L, 1, "build");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TFUNCTION:
                    break;
                case LUA_TNIL:
                    throw new Exception("Recipe misses the mandatory build function");
                default:
                    throw new Exception("Invalid 'build' field: expected a function");
                }
            }
            {
                lua_getfield(L, 1, "package");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TFUNCTION:
                    d.packFunc = true;
                    break;
                case LUA_TNIL:
                    break;
                default:
                    const typ = luaL_typename(L, -1).fromStringz.idup;
                    throw new Exception(
                            "invalid 'package' field: expected a function or nil, got " ~ typ);
                }
            }
            if (revision)
            {
                d.revision = revision;
            }
            else
            {
                lua_getfield(L, 1, "revision");
                scope (exit)
                    lua_pop(L, 1);

                switch (lua_type(L, -1))
                {
                case LUA_TFUNCTION:
                    // will be called from Recipe.revision
                    break;
                case LUA_TNIL:
                    // revision will be lazily computed from the file content in Recipe.revision
                    break;
                default:
                    throw new Exception("Invalid revision specification");
                }
            }

            assert(lua_gettop(L) == 1, "Lua stack not clean");

            // adding the recipe table to the registry
            lua_pushvalue(L, 1);
            lua_setfield(L, LUA_REGISTRYINDEX, "recipe");

            assert(lua_gettop(L) == 1, "Lua stack not clean 2");
        }
        else {
            throw new Exception("Recipe returned multiple results");
        }

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

/// Read a dependency table from top of the stack.
/// The table is left on the stack after return
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
