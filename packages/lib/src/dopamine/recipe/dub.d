module dopamine.recipe.dub;

import dopamine.dep.source;
import dopamine.dep.spec;
import dopamine.log;
import dopamine.pkgconf;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;
import dopamine.util;

import dub.compilers.buildsettings;
import dub.dependency;
import dub.internal.utils;
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
import std.string;
import std.typecons;

DubRecipe parseDubRecipe(string filename, string root, string ver = null)
{
    auto rec = readPackageRecipe(filename);
    rec.version_ = ver ? ver : "0.0.0";
    auto dubPack = new Package(rec, NativePath(absolutePath(root)));
    return new DubRecipe(dubPack);
}

private @property string subPkgName(string name) @safe
{
    const colon = name.indexOf(':');
    if (colon == -1)
        return name;
    else
        return name[colon + 1 .. $];
}

class DubRecipe : Recipe
{
    Package _dubPack;

    private this(Package dubPack)
    {
        _dubPack = dubPack;
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

    @property string description() const @safe
    {
        return (() @trusted => _dubPack.recipe.description)();
    }

    @property string license() const @safe
    {
        return (() @trusted => _dubPack.recipe.license)();
    }

    @property string upstreamUrl() const @safe
    {
        return (() @trusted => _dubPack.recipe.homepage)();
    }

    @property const(string)[] tools() const @safe
    {
        return ["dc"];
    }

    @property const(Option[string]) options() const @safe
    {
        return null;
    }

    @property bool hasDependencies() const @safe
    {
        return (() @trusted => _dubPack.rawRecipe.buildSettings.dependencies.length > 0)();
    }

    @property bool hasDynDependencies() const @safe
    {
        return false;
    }

    private const(DepSpec)[] pkgDependencies(Package pkg, const(ResolveConfig) config)
    {
        const name = _dubPack.name;
        const defaultConfig = pkg.configurations.length ? pkg.configurations[0] : "library";

        auto dubDeps = pkg.getDependencies(defaultConfig);
        return dubDeps.byKeyValue()
            .map!(dd => tuple!("name", "spec")(PackageName(dd.key), dd.value))
            .map!(dd => DepSpec(
                    dd.name,
                    (dd.name.isModule && dd.name.pkgName == name) ?
                    VersionSpec("==" ~ _dubPack.version_.toString()) : adaptDubVersionSpec(dd.spec),
                    DepProvider.dub))
            .array;
    }

    const(DepSpec)[] dependencies(const(ResolveConfig) config) @system
    {
        return pkgDependencies(_dubPack, config);
    }

    @property string[] modules() @trusted
    {
        string[] mods;
        foreach (spkg; _dubPack.subPackages)
        {
            if (spkg.path.empty)
            {
                mods ~= spkg.recipe.name;
            }
            else
            {
                auto pkg = loadSubPackageFromDisk(spkg.path);
                mods ~= pkg.name.subPkgName;
            }
        }
        return mods;
    }

    private Package loadSubPackageFromDisk(string subpkgPath)
    {
        enforce(!isAbsolute(subpkgPath), "Sub package paths must be sub paths of the parent package.");
        auto path = buildNormalizedPath(_dubPack.path.toString(), subpkgPath);
        enforce(exists(path) && isDir(path), format!"No Dub package at %s"(path));

        return Package.load(NativePath(path), NativePath.init, _dubPack);
    }

    private Package loadSubPackage(string modName)
    {
        // As subpkg path and name can differ, there is no way to know
        // which subpackage is modName before actually loading it,
        // so we possibly have to iterate all.
        Package pkg;

        // we start with what is cheap and common guess
        foreach (subPkg; _dubPack.subPackages)
        {
            if (subPkg.path.empty)
            {
                pkg = new Package(subPkg.recipe, _dubPack.path, _dubPack);
            }
            else if (subPkg.path == modName)
            {
                pkg = loadSubPackageFromDisk(subPkg.path);
            }
        }

        if (pkg)
        {
            if (pkg.name.subPkgName == modName)
                return pkg;
        }

        foreach (subPkg; _dubPack.subPackages)
        {
            pkg = loadSubPackageFromDisk(subPkg.path);

            if (pkg.name.subPkgName == modName)
                return pkg;
        }
        throw new NoSuchPackageModuleException(name, modName);
    }

    @property const(DepSpec)[] moduleDependencies(string moduleName, const(ResolveConfig) config) @system
    {
        auto pkg = loadSubPackage(moduleName);
        return pkgDependencies(pkg, config);
    }

    string[] include() @safe
    {
        assert(false, "Not implemented. Dub recipes are not meant to be published by Dopamine");
    }

    @property bool inTreeSrc() const @safe
    {
        return true;
    }

    string source() @system
    {
        return ".";
    }

    string moduleSourceDir(string modName) @trusted
    {
        foreach (subPkg; _dubPack.subPackages)
        {
            if (subPkg.path.empty)
            {
                if (subPkg.recipe.name == modName)
                    return ".";
                continue;
            }
            auto pkg = loadSubPackageFromDisk(subPkg.path);
            if (pkg.name.subPkgName == modName)
                return subPkg.path;
        }
        throw new NoSuchPackageModuleException(_dubPack.name, modName);
    }

    @property bool modulesBatchBuild() @safe
    {
        return true;
    }

    void buildModule(BuildDirs dirs, const(BuildConfig) config, DepGraphBuildInfo depInfos) @system
    {
        auto pack = loadSubPackage(config.modules[0]);
        doBuild(pack, dirs, config, depInfos);
    }

    void build(BuildDirs dirs, const(BuildConfig) config, DepGraphBuildInfo depInfos) @system
    {
        doBuild(_dubPack, dirs, config, depInfos);
    }

    private void doBuild(Package pack, BuildDirs dirs, const(BuildConfig) config, DepGraphBuildInfo depInfos)
    {
        import dub.internal.vibecompat.data.json;

        const platform = config.profile.toDubPlatform();
        const defaultConfig = pack.configurations.length ? pack.configurations[0] : "library";
        auto bs = pack.getBuildSettings(platform, defaultConfig);

        enforce(
            bs.targetType == TargetType.staticLibrary
                || bs.targetType == TargetType.library
                || bs.targetType == TargetType.sourceLibrary,
            new ErrorLogException(
                "Only Dub static and source libraries are supported. %s is a %s",
                pack.name, bs.targetType
        ));

        string builtTarget;
        if (bs.targetType == TargetType.staticLibrary || bs.targetType == TargetType.library)
        {
            builtTarget = buildStaticLibrary(bs, pack, dirs, config, depInfos);
        }

        auto dc = config.profile.toolFor("dc");
        auto dcf = CompilerFlags.fromTool(dc);

        // generate a pkg-config file
        const pkgcId = pack.name.replace(":", "_");
        const pcPath = buildPath(dirs.build, pkgcId ~ ".pc");
        PkgConfFile pkg;
        pkg.addOrSetVar("prefix", dirs.install);
        pkg.addOrSetVar("includedir", "${prefix}/include/d/" ~ pkgcId);
        pkg.addOrSetVar("libdir", "${prefix}/lib");
        pkg.name = pack.name;
        pkg.description = pack.rawRecipe.description;
        pkg.ver = ver.toString();
        foreach (k, v; depInfos.dub)
            pkg.requires ~= format!"%s = %s"(k.replace(':', '_'), v.ver);
        pkg.cflags = bs.importPaths.map!(p => dcf.importPath("${includedir}/" ~ p))
            .chain(bs.versions.map!(v => dcf.version_(v)))
            .array;
        if (builtTarget)
            pkg.libs = ["${libdir}/" ~ builtTarget];
        pkg.writeToFile(pcPath);

        // we drive the installation directly
        installFile(
            pcPath,
            buildPath(dirs.install, "lib", "pkgconfig", pkgcId ~ ".pc")
        );
        if (builtTarget)
            installFile(
                buildPath(dirs.build, builtTarget),
                buildPath(dirs.install, "lib", builtTarget)
            );
        foreach (src; bs.sourceFiles)
            installFile(
                buildPath(dirs.src, src),
                buildPath(dirs.install, "include", "d", pkgcId, src)
            );
    }

    private string buildStaticLibrary(ref BuildSettings bs, Package pack, BuildDirs dirs, const(
            BuildConfig) config, DepGraphBuildInfo depInfos)
    {
        import std.process;

        // build pkg-config search path and collect dependencies requirements
        string pkgconfPath = depInfos.dub.byValue()
            .map!(d => d.installDir)
            .filter!(d => d.length > 0)
            .map!(d => buildPath(d, "lib", "pkgconfig"))
            .array
            .join(pathSeparator);

        auto pkgconfEnv = [
            "PKG_CONFIG_PATH": pkgconfPath,
        ];

        foreach (d; depInfos.dub.byKey())
        {
            auto pkgcId = d.replace(":", "_");
            auto df = execute([pkgConfigExe, "--cflags", pkgcId], pkgconfEnv);
            enforce(df.status == 0, "pkg-config failed: " ~ df.output);
            bs.dflags ~= df.output.strip().split(" ");
            auto lf = execute([pkgConfigExe, "--libs", pkgcId], pkgconfEnv);
            enforce(lf.status == 0, "pkg-config failed " ~ lf.output);
            bs.lflags ~= lf.output.strip().split(" ");
        }

        bs.versions ~= "Have_" ~ stripDlangSpecialChars(pack.name);

        string[string] ninjaEnv;
        config.profile.collectEnvironment(ninjaEnv);

        // we create a ninja file to drive the compilation
        auto nb = createNinja(pack, bs, dirs, config);
        nb.writeToFile(buildPath(dirs.build, "build.ninja"));
        runCommand(["ninja"], dirs.build, LogLevel.verbose, ninjaEnv);

        return libraryFileName(pack.name);
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

    private NinjaBuild createNinja(Package pack, const ref BuildSettings bs, BuildDirs dirs, const(
            BuildConfig) config)
    {
        version (Windows)
        {
            enum objExt = ".obj";
        }
        else
        {
            enum objExt = ".o";
        }

        auto dc = config.profile.toolFor("dc");
        auto dcf = CompilerFlags.fromTool(dc);

        const targetName = libraryFileName(pack.name);

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

        const srcFromBuild = dirs.src.relativePath(dirs.build);
        auto compileArgs = dcf.buildType(config.profile.buildType) ~ dcf.compileArgs(bs, srcFromBuild);
        NinjaTarget[] targets;

        string[] objects;

        foreach (src; bs.sourceFiles)
        {
            const objFile = src ~ objExt;
            const depfile = objFile ~ ".d";

            NinjaTarget target;
            target.target = ninjaEscape(objFile);
            target.rule = dcRule.name;
            target.inputs = [ninjaEscape(buildPath(srcFromBuild, src))];

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

VersionSpec adaptDubVersionSpec(Dependency dubDep)
{
    // Dopamine and dub versions are largely compatible.
    // Sometimes however, Dependency.versionSpec returns
    // a single digit in the version spec (e.g ~>1).
    // We amend that case to make it compatible with VersionSpec.
    string dd = dubDep.versionSpec;
    if (dd != "*" && dd.indexOf('.') == -1)
        dd ~= ".0";
    return VersionSpec(dd);
}

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
    const dc = profile.toolFor("dc");
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

    static CompilerFlags fromTool(const(Tool) dc)
    {
        assert(dc.id == "dc");
        if (dc.name == "DMD")
        {
            return new DmdCompilerFlags;
        }
        if (dc.name == "LDC")
        {
            return new LdcCompilerFlags;
        }
        throw new Exception("Unknown D compiler: " ~ dc.name);
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
        return "--makedeps=" ~ filename;
    }

    string output(string filename)
    {
        return "--of=" ~ filename;
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
        return "--d-version=" ~ ident;
    }

    string debugVersion(string ident)
    {
        return "--d-debug=" ~ ident;
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
    const ln = libname.replace(":", "_");
    version (Windows)
    {
        return ln ~ ".lib";
    }
    else
    {
        return "lib" ~ ln ~ ".a";
    }
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
