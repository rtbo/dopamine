module test.recipe;

import test.profile;
import test.util;

import dopamine.dependency;
import dopamine.profile;
import dopamine.recipe;
import dopamine.util;

import std.file;
import std.path;

private Recipe pkgRecipe(string pkg)
{
    return Recipe.parseFile(testPath("data", pkg, "dopamine.lua"));
}

private BuildDirs pkgBuildDirs(string pkg)
{
    import std.format : format;

    const srcDir = testPath("data", pkg);
    const workDir = testPath("gen", pkg);
    const buildDir = testPath("gen", pkg, "build");
    const installDir = testPath("gen", pkg, "install");
    return BuildDirs(srcDir, workDir, buildDir, installDir);
}

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
    auto recipe = pkgRecipe("pkga");
    const bd = pkgBuildDirs("pkga");
    auto profile = ensureDefaultProfile();

    bd.src.fromDir!({
        recipe.build(bd, profile);
    });
}

@("pkgb.dependencies")
unittest
{
    auto recipe = pkgRecipe("pkgb");

    const rel = ensureDefaultProfile().withBuildType(BuildType.release);
    const deb = rel.withBuildType(BuildType.debug_);

    const relDeps = recipe.dependencies(rel);
    const debDeps = recipe.dependencies(deb);

    assert(relDeps.length == 0);
    assert(debDeps.length == 1);
    assert(debDeps[0] == Dependency("pkga", VersionSpec(">=1.0.0")));
}


@("pkgc.build+pack")
unittest
{
    auto recipe = pkgRecipe("pkgc");
    const bd = pkgBuildDirs("pkgc");

    auto profile = ensureDefaultProfile();

    bd.src.fromDir!({
        recipe.build(bd, profile);
        recipe.pack(bd, profile, bd.install);
    });

    assert(isFile(buildPath(bd.install, "lib", "libpkgc.a")));
    assert(isFile(buildPath(bd.install, "include", "d", "pkgc-1.0.0", "pkgc.d")));
}

