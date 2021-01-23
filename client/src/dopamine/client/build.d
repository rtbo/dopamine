module dopamine.client.build;

import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.client.source;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.state;

import std.exception;
import std.file;
import std.getopt;
import std.path;

string enforceBuildReady(PackageDir dir, ProfileDirs profileDirs)
{
    return enforce(checkBuildReady(dir, profileDirs), new FormatLogException(
            "%s: package is not built for selected profile. Try to run `%s`",
            error("Error"), info("dop build")));
}

int buildMain(string[] args)
{
    string profileName;
    string installDir;
    bool force;

    auto helpInfo = getopt(args, "profile|p", &profileName, "install-dir|i",
            &installDir, "force", &force);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop build command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);

    auto profile = enforceProfileReady(dir, recipe, profileName);
    const profileDirs = dir.profileDirs(profile);

    const buildReady = checkBuildReady(dir, profileDirs);
    if (!force && buildReady)
    {
        logInfo("%s: Already up-to-date at %s (run with %s to overcome)",
                info("Build"), info("buildReady"), info("--force"));
        return 0;
    }

    const srcDir = enforceSourceReady(dir, recipe);

    if (!installDir)
        installDir = profileDirs.install;

    const buildDirs = BuildDirs(srcDir, installDir.absolutePath());

    const buildInfo = recipe.build(buildDirs, profile);
    profileDirs.buildFlag.write(buildInfo);

    logInfo("%s: %s - %s", info("Build"), success("OK"), buildInfo);

    return 0;
}
