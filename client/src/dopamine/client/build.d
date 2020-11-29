module dopamine.client.build;

import dopamine.profile;
import dopamine.recipe;
import dopamine.paths;

import std.algorithm;
import std.array;
import std.digest;
import std.digest.sha;
import std.exception;
import std.file;
import std.format;
import std.getopt;
import std.stdio;

int buildMain(string[] args)
{
    string profileName;

    auto helpInfo = getopt(args, "profile",
            "override profile for this invocation", &profileName,);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop build command", helpInfo.options);
        return 0;
    }

    enforcePackageDefinitionDir();

    if (!exists(userProfileFile("default")))
    {
        writeln("Default profile does not exist. Will create it.");
        auto p = detectDefaultProfile([Lang.d, Lang.cpp, Lang.c], BuildType.release);
        writeln(p.describe());

        p.saveToFile(userProfileFile("default"), false, true);
        writeln("Default profile saved to " ~ userProfileFile("default"));
    }

    writeln("parsing recipe");
    auto recipe = parseRecipe("dopamine.lua");

    Profile profile;

    if (profileName)
    {
        const filename = userProfileFile(profileName);
        enforce(exists(filename), format("Profile %s does not exist", profileName));
        profile = Profile.loadFromFile(filename);
        writeln("loading profile " ~ profile.name);
    }
    else
    {
        const filename = localProfileFile();
        if (!exists(filename))
        {
            writeln("No profile is set, assuming and setting default");
            profile = Profile.loadFromFile(userProfileFile("default"));
            profile.saveToFile(filename, true, true);
        }
        else
        {
            profile = Profile.loadFromFile(filename);
            writeln("loading profile " ~ profile.name);
        }
    }

    assert(profile, "profile not set");

    string srcDir;

    if (recipe.outOfTree)
    {
        // download and set srcDir
    }
    else
    {
        srcDir = ".";
    }

    const buildDir = localBuildDir(profile);
    const installDir = localInstallDir(profile);

    recipe.build.configure(srcDir, buildDir, installDir, profile);
    recipe.build.build();
    recipe.build.install();

    return 0;
}
