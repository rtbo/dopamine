module test.recipe;

import test.util;

import dopamine.depbuild;
import dopamine.depdag;
import dopamine.dependency;
import dopamine.profile;
import dopamine.recipe;
import dopamine.util;

import std.file;
import std.path;

import unit_threaded : should;

@("Read pkga recipe")
unittest
{
    const recipe = pkgRecipe("pkga");

    assert(recipe.name == "pkga");
    assert(recipe.ver == "1.0.0");
}

@("Read pkga revision")
unittest
{
    import std.digest : toHexString, LetterCase;
    import std.digest.sha : sha1Of;

    auto recipe = pkgRecipe("pkga");

    const expected = sha1Of(read(recipe.filename)).toHexString!(LetterCase.lower);

    assert(recipe.revision == expected);
}

@("pkga.source")
unittest
{
    auto recipe = pkgRecipe("pkga");

    assert(recipe.source() == ".");
}

@("pkga.build")
unittest
{
    cleanGen();

    auto recipe = pkgRecipe("pkga");
    const bd = pkgBuildDirs("pkga");
    auto profile = ensureDefaultProfile();

    bd.src.fromDir!({ recipe.build(bd, profile); });
}

@("pkgb.dependencies")
unittest
{
    cleanGen();

    auto recipe = pkgRecipe("pkgb");

    const rel = ensureDefaultProfile().withBuildType(BuildType.release);
    const deb = rel.withBuildType(BuildType.debug_);

    const relDeps = recipe.dependencies(rel);
    const debDeps = recipe.dependencies(deb);

    assert(relDeps.length == 0);
    assert(debDeps.length == 1);
    assert(debDeps[0] == Dependency("pkga", VersionSpec(">=1.0.0")));
}

@("pkgc.pack")
unittest
{
    cleanGen();

    auto recipe = pkgRecipe("pkgc");
    const bd = pkgBuildDirs("pkgc");
    auto profile = ensureDefaultProfile();

    auto cache = new DepCacheMock();
    auto dag = prepareDepDAG(recipe, profile, cache);
    resolveDepDAG(dag, cache);
    auto depInfos = buildDependencies(dag, recipe, profile, cache);

    bd.src.fromDir!({
        recipe.build(bd, profile, depInfos);
        recipe.pack(bd, profile, bd.install);
    });

    assert(isFile(buildPath(bd.install, "lib", "libpkgc.a")));
    assert(isFile(buildPath(bd.install, "include", "d", "pkgc-1.0.0", "pkgc.d")));
}

@("app.pack")
unittest
{
    import dopamine.log : LogLevel;
    import dopamine.util : runCommand;
    import std.process : environment;

    cleanGen();

    auto recipe = pkgRecipe("app");
    const bd = pkgBuildDirs("app");
    const deps = testPath("gen", "app", "deps");
    const pc = testPath("gen", "app", "deps", "lib", "pkgconfig");

    auto profile = ensureDefaultProfile();

    auto cache = new DepCacheMock();
    auto dag = prepareDepDAG(recipe, profile, cache);
    resolveDepDAG(dag, cache);
    buildDependencies(dag, recipe, profile, cache);

    auto depInfos = buildDependencies(dag, recipe, profile, cache, deps);

    string[string] env;
    env["PKG_CONFIG_PATH"] = pc ~ pathSeparator ~ environment.get("PKG_CONFIG_PATH", "");
    profile.collectEnvironment(env);

    runCommand([
            "meson", "setup", bd.build, "--prefix=" ~ bd.install,
            "--buildtype=" ~ profile.buildType.toConfig
            ], bd.src, LogLevel.verbose, env);

    runCommand(["meson", "compile"], bd.build);
    runCommand(["meson", "install"], bd.build);
}
