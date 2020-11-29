module dopamine.client.profile;

import dopamine.paths;
import dopamine.profile;

import std.exception;
import std.getopt;
import std.file;
import std.format;
import std.path;
import std.stdio;

Profile detectAndWriteDefault()
{
    writeln("Detecting default profile");

    auto profile = detectDefaultProfile([Lang.d, Lang.cpp, Lang.c], BuildType.release);
    writeln(profile.describe());

    const path = userProfileFile("default");
    profile.saveToFile(path, false);
    writeln("Default profile saved to " ~ path);

    return profile;
}

int profileMain(string[] args)
{
    bool detectDef;

    auto helpInfo = getopt(args, "detect-default|D", &detectDef);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop profile command", helpInfo.options);
        return 0;
    }

    if (detectDef)
    {
        // detecting default profile and write it in user dir
        detectAndWriteDefault();
    }

    const clProfileName = args.length > 1 ? args[1] : null;

    if (!inPackageDefinitionDir())
    {
        // a few operations are possible out a package directory
        if (detectDef && !clProfileName)
            return 0;
        enforcePackageDefinitionDir();
    }

    const profileName = clProfileName ? clProfileName : "default";
    const profileFile = buildPath(userProfileDir(), profileName ~ ".ini");

    Profile profile;

    if (profileName == "default" && !exists(profileFile))
    {
        profile = detectAndWriteDefault();
    }

    if (!profile && !exists(profileFile))
    {
        throw new Exception("could not find profile matching name " ~ profileName);
    }
    else
    {
        profile = Profile.loadFromFile(profileFile);
    }

    writeln(format("Setting profile %s for %s", profileName, getcwd()));
    profile.saveToFile(localProfileFile(), true);

    return 0;
}
