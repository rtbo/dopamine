module dopamine.client.pack;

import dopamine.client.build;
import dopamine.client.deps;
import dopamine.client.source;
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

    auto lockFileState = enforcedLockFileState(packageDir, recipe);
    auto sourceState = enforcedSourceState(packageDir, recipe);

    auto profileState = new UseProfileState(packageDir, recipe, lockFileState, profile);

    auto buildState = enforcedBuildState(packageDir, recipe, profileState, sourceState);

    auto archiveState = new CreateArchiveState(packageDir, recipe, profileState, buildState);

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
