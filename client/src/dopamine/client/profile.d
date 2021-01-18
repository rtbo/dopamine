module dopamine.client.profile;

import dopamine.client.recipe;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.state;

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

/// Enforce the loading of a profile.
/// If name is null, will load the profile from the profile file in .dop/ directory
/// If name is not null (can be e.g. "default"), will load the profile from the user profile directory
Profile enforceProfileReady(PackageDir dir, Recipe recipe, string name = null)
{
    Profile profile;
    if (!name)
    {
        profile = enforce(checkProfileFile(dir),
                new FormatLogException("%s: %s has no defined profile. Try to run `%s`.",
                    error("Error"), info(recipe.name), info("dop profile")));
        if (profile.name)
        {
            logInfo("%s: %s - %s (%s)", info("Profile"), success("OK"),
                    info(profile.name), dir.profileFile());
        }
        else
        {
            logInfo("%s: %s - %s", info("Profile"), success("OK"), dir.profileFile());
        }
    }
    else
    {
        string pname;
        profile = enforce(checkProfileName(dir, recipe, name, false, &pname),
                new FormatLogException("%s: %s has no defined profile. Try to run `%s`.",
                    error("Error"), info(recipe.name), info("dop profile")));
        logInfo("%s: %s - %s", info("Profile"), success("OK"), info(pname));
    }
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
