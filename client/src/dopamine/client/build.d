module dopamine.client.build;

import dopamine.client.deplock;
import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.client.source;
import dopamine.depbuild;
import dopamine.depcache;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.state;

import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.typecons;

FlagState enforceBuildReady(PackageDir dir, ProfileDirs profileDirs)
{
    return enforce(checkBuildReady(dir, profileDirs), new FormatLogException(
            "%s: package is not built for selected profile. Try to run `%s`",
            error("Error"), info("dop build")));
}

int buildMain(string[] args)
{
    string profileName;
    bool force;
    bool noNetwork;

    auto helpInfo = getopt(args, "profile|p", &profileName, "force|f",
            &force, "no-network|N", &noNetwork);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop build command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);

    auto profile = enforceProfileReady(dir, recipe, profileName);
    const profileDirs = dir.profileDirs(profile);

    const buildState = checkBuildReady(dir, profileDirs);
    if (!force && buildState)
    {
        logInfo("%s: Already up-to-date (run with %s to overcome)", info("Build"), info("--force"));
        return 0;
    }

    const srcDir = enforceSourceReady(dir, recipe);

    const network = noNetwork ? No.network : Yes.network;
    auto cache = new DependencyCache(network);
    scope (exit)
        cache.dispose();

    DepInfo[string] depInfos;

    if (recipe.hasDependencies)
    {
        auto dag = enforceLoadLockFile(dir, recipe, profile, cache);
        logInfo("Building dependencies...");
        depInfos = buildDependencies(dag, recipe, profile, cache);
        logInfo("%s: %s", info("Dependencies"), success("OK"));
    }

    const buildDirs = profileDirs.buildDirs(srcDir);
    const installDir = buildDirs.install;

    logInfo("Building %s...", info(recipe.name));
    const installed = recipe.build(buildDirs, profile, depInfos);

    if (installed)
    {
        enforce(exists(installDir) && isDir(installDir), new FormatLogException(
                "%s: Build reports installation but the install directory does not exist!",
                error("Error")));
    }
    else
    {
        enforce(recipe.hasPackFunc, new FormatLogException(
                "%s: Build did not install, recipe must have a 'package' function", error("Error")));
    }

    profileDirs.buildFlag.write(installed ? profileDirs.install : "");

    logInfo("%s: %s%s", info("Build"), success("OK"), installed ? " - " ~ profileDirs.install : "");

    return 0;
}
