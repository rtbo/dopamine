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

    writeln("parsing recipe");
    auto recipe = recipeParseFile("dopamine.lua");

    auto langs = recipe.langs.toLangs();

    const defaultName = defaultProfileName(langs);
    const defaultFile = userProfileFile(defaultName);

    if (!exists(defaultFile))
    {
        writeln("Default profile does not exist. Will create it.");
        auto p = detectDefaultProfile(langs);
        writeln(p.describe());

        p.saveToFile(defaultFile, false, true);
        writeln("Default profile saved to " ~ defaultFile);
    }

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
            profile = Profile.loadFromFile(defaultFile);
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
        import dopamine.source : readSourceFlagFile;

        srcDir = readSourceFlagFile();
        enforce(srcDir && exists(srcDir) && isDir(srcDir),
                "source code not available. Try to run `dop source`");
    }
    else
    {
        srcDir = ".";
    }

    const dirs = localProfileDirs(profile);

    recipe.build.configure(srcDir, dirs, profile);
    recipe.build.build(dirs);
    recipe.build.install(dirs);

    return 0;
}
