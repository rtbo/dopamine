module dopamine.client.profile;

import dopamine.client.recipe;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;

import std.exception;
import std.getopt;
import std.file;
import std.format;

Profile detectAndWriteDefault(Lang[] langs)
{
    import std.algorithm : map;
    import std.array : join;
    import std.conv : to;

    logInfo("Detecting default profile for %s", info(langs.map!(l => l.to!string).join(", ")));

    auto profile = detectDefaultProfile(langs);
    logInfo(profile.describe());

    const name = profile.name;
    const path = userProfileFile(name);
    profile.saveToFile(path, false, true);
    logInfo("Default profile saved to %s", info(path));

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

    const packageDir = PackageDir.enforced(".");

    const recipe = parseRecipe(packageDir);

    auto langs = recipe.langs.dup;

    if (detectDef)
    {
        // detecting default profile and write it in user dir
        detectAndWriteDefault(langs);
    }

    const defaultName = profileDefaultName(langs);

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

    logInfo("Setting profile %s for %s", info(profileName), info(getcwd()));
    profile.saveToFile(packageDir.profileFile(), true, true);

    return 0;
}
