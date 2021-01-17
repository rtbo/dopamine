module test.recipe;

import test.profile;
import test.util;

import dopamine.dependency;
import dopamine.profile;
import dopamine.recipe;

import std.file;

shared static this()
{
    import dopamine.lua : initLua;

    initLua();
}

Recipe pkgRecipe(string pkg)
{
    return Recipe.parseFile(testPath("data", pkg, "dopamine.lua"));
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

    const srcDir = testPath("data/pkga");
    const buildDir = testPath("gen/pkga/build");
    const installDir = testPath("gen/pkga/install");
    auto profile = ensureDefaultProfile();

    mkdirRecurse(buildDir);

    recipe.build(profile, srcDir, buildDir, installDir);
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
