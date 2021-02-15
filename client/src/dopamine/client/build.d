module dopamine.client.build;

import dopamine.client.depinstall;
import dopamine.client.deplock;
import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.client.source;
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
    bool noNetwork;

    auto helpInfo = getopt(args, "profile|p", &profileName, "install-dir|i",
            &installDir, "force", &force, "no-network|N", &noNetwork);

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
                info("Build"), info(buildReady), info("--force"));
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

    if (!installDir)
        installDir = profileDirs.install;

    const buildDirs = BuildDirs(srcDir, installDir.absolutePath());
    logInfo("Building %s...", info(recipe.name));
    const buildInfo = recipe.build(buildDirs, profile, depInfos);

    enforce(exists(buildInfo) && isDir(buildInfo), new FormatLogException(
            "%s: Build successful but the build function did not return the install directory!",
            error("Error")));

    profileDirs.buildFlag.write(buildInfo);

    logInfo("%s: %s - %s", info("Build"), success("OK"), buildInfo);

    return 0;
}
