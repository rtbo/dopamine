module dopamine.client.pack;

import dopamine.client.build;
import dopamine.client.deps;
import dopamine.client.profile;
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

string enforceArchiveReady(PackageDir dir, const(Recipe) recipe, Profile profile)
{
    const archiveFile =checkArchiveReady(dir, recipe, profile);
    enforce(archiveFile,
            new FormatLogException("%s: archive file %s not ready. Try to run `%s`.",
                error("Error"), info(dir.archiveFile(profile, recipe)), info("dop pack")));
    logInfo("%s: %s - %s", info("Archive"), success("OK"), archiveFile);
    return archiveFile;
}

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

    auto deps = enforceDepsLocked(packageDir, recipe);

    auto profile = enforceProfileReady(packageDir, recipe, deps, profileName);

    enforceBuildReady(packageDir, recipe, profile);

    if (const archiveFile = checkArchiveReady(packageDir, recipe, profile))
    {
        logInfo("archive %s already created\nNothing to do.", archiveFile);
    }
    else
    {
        const file = packageDir.archiveFile(profile, recipe);
        const dirs = packageDir.profileDirs(profile);

        ArchiveBackend.get.create(dirs.install, file);

        logInfo("Created archive %s", file);
    }

    return 0;
}
