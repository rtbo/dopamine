module dopamine.client.build;

import dopamine.profile;
import dopamine.paths;
import dopamine.recipe;
import dopamine.state;

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

    const packageDir = PackageDir.enforced(".");

    writeln("parsing recipe");
    auto recipe = recipeParseFile(packageDir.dopamineFile());

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
        writeln("Loading profile " ~ profile.name);
    }
    else
    {
        const filename = packageDir.profileFile();
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

    auto profileState = new UseProfileState(packageDir, recipe, profile);
    auto sourceState = new EnforcedSourceState(packageDir, recipe,
            "Source code not available. Try to run `dop source`");
    auto configState = new DoConfigState(packageDir, recipe, profileState, sourceState);
    auto buildState = new DoBuildState(packageDir, recipe, profileState, configState);
    auto installState = new DoInstallState(packageDir, recipe, profileState, buildState);

    const dirs = packageDir.profileDirs(profile);

    if (installState.reached)
    {
        writefln("Target already installed in %s", dirs.install);
    }
    else
    {
        installState.reach();
        writefln("Installed target in %s", dirs.install);
    }

    return 0;
}
