module dopamine.client.pack;

import dopamine.client.util;

import dopamine.archive;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.state;

import std.exception;
import std.getopt;
import std.file;
import std.format;
import std.stdio;

int packageMain(string[] args)
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
        enforce(exists(filename), "Profile not selected");
        profile = Profile.loadFromFile(filename);
    }

    assert(profile);

    auto profileState = new UseProfileState(packageDir, recipe, profile);
    auto sourceState = new EnforcedSourceState(packageDir, recipe,
            "Source code not available. Try to run `dop source`");
    auto configState = new EnforcedConfigState(packageDir, recipe, profileState, sourceState,
            format("Package not configured for profile '%s'. Try to run `dop build`", profile.name));
    auto buildState = new EnforcedBuildState(packageDir, recipe, profileState, configState,
            format("Package not built for profile '%s'. Try to run `dop build`", profile.name));
    auto installState = new EnforcedInstallState(packageDir, recipe, profileState, buildState,
            format("Package not installed for profile '%s'. Try to run `dop build`", profile.name));

    auto archiveState = new CreateArchiveState(packageDir, recipe, profileState, installState);

    if (archiveState.reached)
    {
        logInfo("archive %s already created\nNothing to do.", archiveState.file);
    }
    else {
        archiveState.reach();
        logInfo("Created archive %s", archiveState.file);
    }
    return 0;
}
