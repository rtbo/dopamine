module dopamine.recipe.dub;

import dopamine.dep.spec;
import dopamine.log;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;
import dopamine.util;

import dub.compilers.buildsettings;
import dub.internal.vibecompat.inet.path;
import dub.package_;
import dub.platform;
import dub.recipe.io;
import dub.recipe.packagerecipe;

import std.algorithm;
import std.array;
import std.exception;
import std.file;
import std.path;
import std.range;
import std.stdio : File;

DubRecipe parseDubRecipe(string filename, string root, string ver = null)
{
    auto rec = readPackageRecipe(filename);
    rec.version_ = ver ? ver : "0.0.0";
    auto dubPack = new Package(rec, NativePath(absolutePath(root)));
    return new DubRecipe(dubPack);
}

class DubRecipe : Recipe
{
    Package _dubPack;
    string _defaultConfig;

    private this(Package dubPack)
    {
        _dubPack = dubPack;
        _defaultConfig = _dubPack.configurations[0];
    }

    @property RecipeType type() const @safe
    {
        return RecipeType.dub;
    }

    @property bool isLight() const @safe
    {
        return false;
    }

    @property string name() const @safe
    {
        return (() @trusted => _dubPack.name)();
    }

    @property Semver ver() const @safe
    {
        return (() @trusted => Semver(_dubPack.version_.toString()))();
    }

    @property string revision() const @safe
    {
        return null;
    }

    @property void revision(string rev) @safe
    {
        assert(false, "Dub recipes have no revision");
    }

    @property const(Lang)[] langs() const @safe
    {
        return [Lang.d];
    }

    @property bool hasDependencies() const @safe
    {
        return (() @trusted => _dubPack.rawRecipe.buildSettings.dependencies.length > 0)();
    }

    const(DepSpec)[] dependencies(const(Profile) profile) @system
    {
        auto dubDeps = _dubPack.getDependencies(_defaultConfig);
        return dubDeps.byKeyValue().map!(dd => DepSpec(dd.key, VersionSpec(dd.value.versionSpec), true))
            .array;
    }

    string[] include() @safe
    {
        assert(false, "Not implemented. Dub recipes are not meant to be published");
    }

    @property bool inTreeSrc() const @safe
    {
        return true;
    }

    string source() @system
    {
        return ".";
    }

    void build(BuildDirs dirs, BuildConfig config, DepInfo[string] depInfos = null) @system
    {
        const platform = config.profile.toDubPlatform();
        auto bs = _dubPack.getBuildSettings(platform, _defaultConfig);

        enforce(
            bs.targetType == TargetType.staticLibrary || bs.targetType == TargetType.library,
            new ErrorLogException(
                "Only Dub static libraries are supported. %s is a %s",
                name, bs.targetType
        ));

        string[string] env;
        config.profile.collectEnvironment(env);

        // we create a ninja file to drive the compilation
        auto nb = createNinja(bs, dirs, config);
        nb.writeToFile(buildPath(dirs.build, "build.ninja"));
        runCommand(["ninja"], dirs.build, LogLevel.verbose, env);

        auto dc = config.profile.compilerFor(Lang.d);
        auto dcf = CompilerFlags.fromCompiler(dc);

        const builtTarget = libraryFileName(name);

        // generate a pkg-config file
        const pcPath = buildPath(dirs.build, name ~ ".pc");
        PkgConfig pkg;
        pkg.prefix = dirs.install;
        pkg.name = name;
        pkg.description = _dubPack.rawRecipe.description;
        pkg.ver = ver.toString();
        pkg.includeDir = buildPath("${prefix}", "include", "d", name);
        pkg.libDir = buildPath("${prefix}", "lib");
        pkg.cflags = bs.importPaths.map!(p => dcf.importPath(buildPath("${includedir}", p)))
            .chain(bs.versions.map!(v => dcf.version_(v)))
            .array
            .join(" ");
        pkg.libs = buildPath(dirs.install, "lib", builtTarget);
        pkg.writeToFile(pcPath);

        // we drive the installation directly
        installFile(
            pcPath,
            buildPath(dirs.install, "lib", "pkgconfig", name ~ ".pc")
        );
        installFile(
            buildPath(dirs.build, builtTarget),
            buildPath(dirs.install, "lib", builtTarget)
        );
        foreach (src; bs.sourceFiles)
            installFile(
                buildPath(dirs.root, src),
                buildPath(dirs.install, "include", "d", name, src)
            );
    }

    @property bool canStage() const @safe
    {
        return true;
    }

    void stage(string src, string dest) @system
    {
        import dopamine.util;

        return installRecurse(src, dest);
    }

    private NinjaBuild createNinja(const ref BuildSettings bs, BuildDirs dirs, BuildConfig config)
    {
        version (Windows)
        {
            enum objExt = ".obj";
        }
        else
        {
            enum objExt = ".o";
        }

        auto dc = config.profile.compilerFor(Lang.d);
        auto dcf = CompilerFlags.fromCompiler(dc);

        const targetName = libraryFileName(name);

        NinjaRule dcRule;
        dcRule.name = "compile_D";
        dcRule.command = [
            ninjaQuote(dc.path), "$ARGS", dcf.makedeps("$DEPFILE"), dcf.compile(),
            dcf.output("$out"), "$in"
        ];
        dcRule.depfile = "$DEPFILE_UNQUOTED";
        dcRule.deps = "gcc";
        dcRule.description = "Compiling D object $in";

        NinjaRule ldRule;
        ldRule.name = "link_D";
        ldRule.command = [
            ninjaQuote(dc.path), "$ARGS", dcf.output("$out"), "$in", "$LINK_ARGS"
        ];
        ldRule.description = "Linking $in";

        const rootFromBuild = dirs.root.relativePath(dirs.build);
        auto compileArgs = dcf.buildType(config.profile.buildType) ~ dcf.compileArgs(bs, rootFromBuild);
        NinjaTarget[] targets;

        string[] objects;

        foreach (src; bs.sourceFiles)
        {
            const objFile = src ~ objExt;
            const depfile = objFile ~ ".d";

            NinjaTarget target;
            target.target = ninjaEscape(objFile);
            target.rule = dcRule.name;
            target.inputs = [ninjaEscape(buildPath(rootFromBuild, src))];

            target.variables["ARGS"] = ninjaQuote(compileArgs);
            target.variables["DEPFILE"] = ninjaQuote(depfile);
            target.variables["DEPFILE_UNQUOTED"] = depfile;
            targets ~= target;

            objects ~= objFile;
        }

        NinjaTarget ldTarget;
        ldTarget.target = ninjaEscape(targetName);
        ldTarget.rule = ldRule.name;
        ldTarget.inputs = objects;
        ldTarget.variables["ARGS"] = ninjaQuote(
            dcf.buildType(config.profile.buildType)
                .chain(bs.libs.map!(f => dcf.lib(f)))
                .array
        );
        ldTarget.variables["LINK_ARGS"] = ninjaQuote(
            dcf.linkArgs(bs)
        );
        targets ~= ldTarget;

        return NinjaBuild("1.8.2", [dcRule, ldRule], targets);

    }
}

private:

static this()
{
    import dub.compilers.compiler : registerCompiler;
    import dub.compilers.dmd : DMDCompiler;
    import dub.compilers.gdc : GDCCompiler;
    import dub.compilers.ldc : LDCCompiler;

    registerCompiler(new DMDCompiler);
    registerCompiler(new GDCCompiler);
    registerCompiler(new LDCCompiler);
}

BuildPlatform toDubPlatform(const(Profile) profile)
{
    BuildPlatform res;

    final switch (profile.hostInfo.os)
    {
    case OS.linux:
        res.platform = ["linux"];
        break;
    case OS.windows:
        res.platform = ["windows"];
        break;
    }
    final switch (profile.hostInfo.arch)
    {
    case Arch.x86:
        res.platform = ["x86"];
        break;
    case Arch.x86_64:
        res.platform = ["x86_64"];
        break;
    }
    const dc = profile.compilerFor(Lang.d);
    res.compiler = baseName(dc.path).stripExtension;
    res.compilerBinary = dc.path;
    res.compilerVersion = dc.ver;

    return res;
}

interface CompilerFlags
{
    string[] buildType(BuildType bt);

    string compile();
    string output(string filename);
    string makedeps(string filename);
    string importPath(string path);
    string stringImportPath(string path);
    string version_(string ident);
    string debugVersion(string ident);

    string lib(string name);
    string libSearchPath(string path);
    string staticLib();

    static CompilerFlags fromCompiler(const(Compiler) dc)
    {
        if (dc.name == "DMD")
        {
            return new DmdCompilerFlags;
        }
        if (dc.name == "LDC")
        {
            return new LdcCompilerFlags;
        }
        throw new Exception("Unknown Dub compiler: " ~ dc.name);
    }

    final const(string)[] compileArgs(const ref BuildSettings bs, string prefix)
    {
        string[] res;
        res ~= bs.importPaths.map!(f => this.importPath(buildPath(prefix, f))).array;
        res ~= bs.stringImportPaths.map!(f => this.stringImportPath(buildPath(prefix, f))).array;
        res ~= bs.versions.map!(f => this.version_(f)).array;
        res ~= bs.debugVersions.map!(f => this.debugVersion(f)).array;
        res ~= bs.dflags;
        return res;
    }

    final const(string)[] linkArgs(const ref BuildSettings bs)
    {
        return only(this.staticLib())
            .chain(bs.lflags)
            .array;
    }
}

class DmdCompilerFlags : CompilerFlags
{
    string[] buildType(BuildType bt)
    {
        final switch (bt)
        {
        case BuildType.debug_:
            return ["-debug", "-g"];
        case BuildType.release:
            return ["-release"];
        }
    }

    string compile()
    {
        return "-c";
    }

    string makedeps(string filename)
    {
        return "-makedeps=" ~ filename;
    }

    string output(string filename)
    {
        return "-of=" ~ filename;
    }

    string importPath(string path)
    {
        return "-I" ~ path;
    }

    string stringImportPath(string path)
    {
        return "-J" ~ path;
    }

    string version_(string ident)
    {
        return "-version=" ~ ident;
    }

    string debugVersion(string ident)
    {
        return "-debug=" ~ ident;
    }

    string libSearchPath(string path)
    {
        return "-L-L" ~ path;
    }

    string lib(string name)
    {
        return "-L-l" ~ name;
    }

    string staticLib()
    {
        return "-lib";
    }
}

class LdcCompilerFlags : CompilerFlags
{
    string[] buildType(BuildType bt)
    {
        final switch (bt)
        {
        case BuildType.debug_:
            return ["-d-debug", "-g"];
        case BuildType.release:
            return ["-release"];
        }
    }

    string compile()
    {
        return "-c";
    }

    string makedeps(string filename)
    {
        return "-makedeps=" ~ filename;
    }

    string output(string filename)
    {
        return "-of=" ~ filename;
    }

    string importPath(string path)
    {
        return "-I=" ~ path;
    }

    string stringImportPath(string path)
    {
        return "-J=" ~ path;
    }

    string version_(string ident)
    {
        return "-version=" ~ ident;
    }

    string debugVersion(string ident)
    {
        return "-debug=" ~ ident;
    }

    string libSearchPath(string path)
    {
        return "-L=-L" ~ path;
    }

    string lib(string name)
    {
        return "-L=-l" ~ name;
    }

    string staticLib()
    {
        return "-lib";
    }
}

string libraryFileName(string libname)
{
    return "lib" ~ libname ~ ".a";
}

string ninjaQuote(string arg)
{
    if (arg.canFind(" "))
        return `"` ~ arg ~ `"`;
    return arg;
}

string ninjaQuote(const(string)[] args)
{
    return args.map!(a => ninjaEscape(a)).array.join(" ");
}

string ninjaEscape(string arg)
{
    return arg
        .replace(" ", "$ ")
        .replace(":", "$:");
}

string ninjaEscape(const(string)[] args)
{
    return args.map!(a => ninjaEscape(a)).array.join(" ");
}

struct NinjaRule
{
    string name;
    string[] command;
    string deps;
    string depfile;
    string description;
    string pool;

    void write(File file) const
    {
        file.writeln();
        file.writefln!"rule %s"(name);
        file.writefln!"  command = %s"(command.join(" "));
        if (depfile)
            file.writefln!"  depfile = %s"(depfile);
        if (deps)
            file.writefln!"  deps = %s"(deps);
        file.writefln!"  description = %s"(description);
        if (pool)
            file.writefln!"  pool = %s"(pool);
    }
}

struct NinjaTarget
{
    string target;
    string rule;
    string[] inputs;
    string[] implicitDeps;
    string[] orderOnlyDeps;
    string[string] variables;

    void write(File file) const
    {
        file.writeln();
        file.writef!"build %s: %s %s"(ninjaEscape(target), rule, ninjaEscape(inputs));
        if (implicitDeps)
            file.writef!" | %s"(ninjaEscape(implicitDeps));
        if (orderOnlyDeps)
            file.writef!" || %s"(ninjaEscape(orderOnlyDeps));
        file.writeln();
        string[] vars = variables.keys;
        sort(vars);
        foreach (v; vars)
        {
            file.writefln!"  %s = %s"(v, variables[v]);
        }
    }
}

struct NinjaBuild
{
    string requiredVersion;
    NinjaRule[] rules;
    NinjaTarget[] targets;

    void writeToFile(string filename)
    {
        import std.stdio : File;

        auto file = File(filename, "w");

        file.writefln!"ninja_required_version = %s"(requiredVersion);
        rules.each!(r => r.write(file));
        targets.each!(r => r.write(file));
    }
}
