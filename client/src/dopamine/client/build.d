module dopamine.client.build;

import dopamine.client.util;

import dopamine.log;
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

    const recipe = parseRecipe(packageDir);

    auto langs = recipe.langs.toLangs();

    const defaultName = defaultProfileName(langs);
    const defaultFile = userProfileFile(defaultName);

    if (!exists(defaultFile))
    {
        logInfo("Default profile does not exist. Will create it.");
        auto p = detectDefaultProfile(langs);
        logInfo(p.describe());

        p.saveToFile(defaultFile, false, true);
        logInfo("Default profile saved to %s", info(defaultFile));
    }

    Profile profile;

    if (profileName)
    {
        const filename = userProfileFile(profileName);
        enforce(exists(filename), format("Profile %s does not exist", profileName));
        profile = Profile.loadFromFile(filename);
    }
    else
    {
        const filename = packageDir.profileFile();
        if (!exists(filename))
        {
            logInfo("No profile is set, assuming and setting default");
            profile = Profile.loadFromFile(defaultFile);
            profile.saveToFile(filename, true, true);
        }
        else
        {
            profile = Profile.loadFromFile(filename);
        }
    }

    assert(profile, "profile not set");

    auto profileState = new UseProfileState(packageDir, recipe, profile);
    auto sourceState = new EnforcedSourceState(packageDir, recipe,
            "Source code not available or not up-to-date. Try to run `dop source`");
    auto configState = new DoConfigState(packageDir, recipe, profileState, sourceState);
    auto buildState = new DoBuildState(packageDir, recipe, profileState, configState);
    auto installState = new DoInstallState(packageDir, recipe, profileState, buildState);

    const dirs = packageDir.profileDirs(profile);

    if (installState.reached)
    {
        logInfo("Target already installed in %s\nNothing to do.", info(dirs.install));
    }
    else
    {
        installState.reach();
        logInfo("Installed target in %s", info(dirs.install));
    }

    return 0;
}
