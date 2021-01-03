module dopamine.client.build;

import dopamine.client.deps;
import dopamine.client.source;
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

/// Enforces that a build is ready and installed.
string enforceBuildReady(PackageDir dir, const(Recipe) recipe, Profile profile)
{
    const pdirs = dir.profileDirs(profile);

    enforce(checkConfigReady(dir, pdirs),
            new FormatLogException("%s: Package %s not configured for profile '%s'. Try to run `%s`",
                error("Error"), info(recipe.name), info(profile.name), info("dop build")));
    enforce(checkBuildReady(dir, pdirs),
            new FormatLogException("%s: Package %s not built for profile '%s'. Try to run `%s`",
                error("Error"), info(recipe.name), info(profile.name), info("dop build")));
    enforce(checkInstallReady(dir, pdirs),
            new FormatLogException("%s: Package %s not installed for profile '%s'. Try to run `%s`",
                error("Error"), info(recipe.name), info(profile.name), info("dop build")));

    return pdirs.install;
}

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

    const deps = enforceDepsLocked(packageDir, recipe);

    Lang[] langs = deps.resolvedNode.langs.dup;

    const defaultName = profileDefaultName(langs);
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

    auto sourceDir = enforceSourceDirReady(packageDir, recipe);

    const dirs = packageDir.profileDirs(profile);

    if (!checkConfigReady(packageDir, dirs))
        recipe.build.configure(sourceDir, dirs, profile);
    if (!checkBuildReady(packageDir, dirs))
        recipe.build.build(dirs);
    if (!checkInstallReady(packageDir, dirs))
    {
        recipe.build.install(dirs);
        logInfo("Installed target in %s", info(dirs.install));
    }
    else
    {
        // can only be reached if package was configured AND built AND installed
        logInfo("Target already installed in %s\nNothing to do.", info(dirs.install));
    }

    return 0;
}
