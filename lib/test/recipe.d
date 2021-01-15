module test.recipe;

import test.profile;
import test.util;

import dopamine.recipe;

import std.file;

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
