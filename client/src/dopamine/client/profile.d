module dopamine.client.profile;

import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;

import std.exception;
import std.getopt;
import std.file;
import std.format;
import std.path;
import std.stdio;

Profile detectAndWriteDefault(Lang[] langs)
{
    writeln("Detecting default profile");

    auto profile = detectDefaultProfile(langs);
    writeln(profile.describe());

    const name = profile.name;
    const path = userProfileFile(name);
    profile.saveToFile(path, false, true);
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

    enforcePackageDefinitionDir();

    writeln("parsing recipe");
    auto recipe = recipeParseFile("dopamine.lua");

    auto langs = recipe.langs.toLangs();

    if (detectDef)
    {
        // detecting default profile and write it in user dir
        detectAndWriteDefault(langs);
    }

    const defaultName = defaultProfileName(langs);

    const clProfileName = args.length > 1 ? args[1] : null;

    const profileName = clProfileName ? clProfileName : defaultName;
    const profileFile = userProfileFile(profileName);

    Profile profile;

    if (profileName == defaultName && !exists(profileFile))
    {
        profile = detectAndWriteDefault(langs);
    }

    enforce(profile || exists(profileFile),
            format(`could not find profile matching name "%s"`, profileName));

    if (!profile)
    {
        profile = Profile.loadFromFile(profileFile);
    }

    writeln(format(`Setting profile "%s" for %s`, profileName, getcwd()));
    profile.saveToFile(localProfileFile("."), true, true);

    return 0;
}
