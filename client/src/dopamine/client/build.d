module dopamine.client.build;

import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.client.source;
import dopamine.log;
import dopamine.paths;
import dopamine.state;

import std.file;
import std.getopt;
import std.path;

int buildMain(string[] args)
{
    string profileName;
    string buildDir;
    string installDir;
    bool force;

    auto helpInfo = getopt(args, "profile|p", &profileName, "build-dir|b",
            &buildDir, "install-dir|i", &installDir, "force", &force);

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

    const cwd = getcwd();

    const srcDir = enforceSourceReady(dir, recipe).absolutePath(cwd);

    if (!buildDir)
        buildDir = profileDirs.build;

    if (!installDir)
        installDir = profileDirs.install;

    buildDir = buildDir.absolutePath(cwd);
    installDir = installDir.absolutePath(cwd);

    const buildInfo = recipe.build(profile, srcDir, buildDir, installDir).relativePath(cwd);
    profileDirs.buildFlag.write(buildInfo);

    logInfo("%s: %s - %s", info("Build"), success("OK"), buildInfo);

    return 0;
}
