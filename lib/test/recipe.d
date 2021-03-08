module test.recipe;

import test.util;

import dopamine.depbuild;
import dopamine.depdag;
import dopamine.dependency;
import dopamine.profile;
import dopamine.recipe;
import dopamine.util;

import exceptionhandling;

import std.file;
import std.path;

@("Read light1 deps")
unittest
{
    auto recipe = testRecipe("light1");
    const profile = ensureDefaultProfile();

    assertEqual(recipe.type, RecipeType.light);
    assert(recipe.hasDependencies);
    const deps = recipe.dependencies(profile);
    const expected = [Dependency("pkga", VersionSpec(">=1.0.0")),];
    assertEqual(deps, expected);
}

@("Read light2 deps")
unittest
{
    auto recipe = testRecipe("light2");
    const profile = ensureDefaultProfile();
    const debugProf = profile.withBuildType(BuildType.debug_);
    const releaseProf = profile.withBuildType(BuildType.release);

    assertEqual(recipe.type, RecipeType.light);
    assert(recipe.hasDependencies);
    const debugDeps = recipe.dependencies(debugProf);
    const debugExpected = [Dependency("pkga", VersionSpec(">=1.0.0")),];
    assertEqual(debugDeps, debugExpected);

    const releaseDeps = recipe.dependencies(releaseProf);
    const Dependency[] releaseExpected;
    assertEqual(releaseDeps, releaseExpected);
}

@("Read pkga recipe")
unittest
{
    const recipe = testRecipe("pkga");

    assertEqual(recipe.name, "pkga");
    assertEqual(recipe.ver, "1.0.0");
    assertEqual(recipe.langs, [Lang.c]);
}

@("Read pkga revision")
unittest
{
    import std.digest : toHexString, LetterCase;
    import std.digest.sha : sha1Of;

    auto recipe = testRecipe("pkga");

    const expected = sha1Of(read(recipe.filename)).toHexString!(LetterCase.lower);

    assert(recipe.revision == expected);
}

@("pkga.source")
unittest
{
    auto recipe = testRecipe("pkga");

    assert(recipe.source() == ".");
}

@("pkga.build")
unittest
{
    cleanGen();

    auto recipe = testRecipe("pkga");
    const bd = testBuildDirs("pkga");
    auto profile = ensureDefaultProfile();

    bd.src.fromDir!({ recipe.build(bd, profile); });
}

@("pkgb.dependencies")
unittest
{
    cleanGen();

    auto recipe = testRecipe("pkgb");

    const rel = ensureDefaultProfile().withBuildType(BuildType.release);
    const deb = rel.withBuildType(BuildType.debug_);

    const relDeps = recipe.dependencies(rel);
    const debDeps = recipe.dependencies(deb);

    assert(relDeps.length == 0);
    assert(debDeps.length == 1);
    assert(debDeps[0] == Dependency("pkga", VersionSpec(">=1.0.0")));
}

@("pkgc.package")
unittest
{
    cleanGen();

    auto recipe = testRecipe("pkgc");
    const bd = testBuildDirs("pkgc");
    auto profile = ensureDefaultProfile();

    auto cache = new DepCacheMock();
    auto dag = prepareDepDAG(recipe, profile, cache);
    resolveDepDAG(dag, cache);
    auto depInfos = buildDependencies(dag, recipe, profile, cache);

    bd.src.fromDir!({
        recipe.build(bd, profile, depInfos);
        recipe.pack(bd.toPack(), profile, depInfos);
    });

    version(Windows)
    {
        const libfile = buildPath(bd.install, "lib", "pkgc.lib");
    }
    else
    {
        const libfile = buildPath(bd.install, "lib", "libpkgc.a");
    }

    assert(isFile(libfile));
    assert(isFile(buildPath(bd.install, "include", "d", "pkgc-1.0.0", "pkgc.d")));
}

// deactivating this test on Windows because of a bug in Meson
version(Windows)
{}
else
{
    @("app.package")
    unittest
    {
        import dopamine.log : LogLevel;
        import dopamine.util : runCommand;
        import std.process : environment;

        cleanGen();

        auto recipe = testRecipe("app");
        const bd = testBuildDirs("app");
        const deps = testPath("gen", "app", "deps");
        const pc = testPath("gen", "app", "deps", "lib", "pkgconfig");

        auto profile = ensureDefaultProfile();

        auto cache = new DepCacheMock();
        auto dag = prepareDepDAG(recipe, profile, cache);
        resolveDepDAG(dag, cache);

        buildDependencies(dag, recipe, profile, cache, deps);

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
}

