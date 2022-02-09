module test.util;

import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.file;
import std.path;

string testPath(Args...)(Args args)
{
    return buildNormalizedPath(dirName(__FILE_FULL_PATH__), args);
}

Recipe testRecipe(string name)
{
    return Recipe.parseFile(testPath("recipes", name, "dopamine.lua"));
}

BuildDirs testBuildDirs(string name)
{
    import std.format : format;

    const srcDir = testPath("recipes", name);
    const workDir = testPath("gen", name);
    const buildDir = testPath("gen", name, "build");
    const installDir = testPath("gen", name, "install");
    return BuildDirs(srcDir, workDir, buildDir, installDir);
}

Profile ensureDefaultProfile()
{
    const path = testPath("gen/profile/default.ini");
    if (exists(path))
    {
        return Profile.loadFromFile(path);
    }
    auto profile = detectDefaultProfile([Lang.d, Lang.cpp, Lang.c]);
    profile.saveToFile(path, true, true);
    return profile;
}

void cleanGen()
{
    const genPath = testPath("gen");
    if (exists(genPath))
        rmdirRecurse(genPath);
}

/// execute pred from directory dir
/// and chdir back to the previous dir afterwards
/// Returns: whatever pred returns
auto fromDir(alias pred)(string dir) @system
{
    // shortcut if chdir is not needed
    if (dir == ".")
        return pred();

    const cwd = getcwd();
    chdir(dir);
    scope (exit)
        chdir(cwd);

    return pred();
}
