module dopamine.client.pack;

import dopamine.archive;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;

import std.exception;
import std.getopt;
import std.file;
import std.format;
import std.stdio;

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

    writeln("parsing recipe");
    auto recipe = recipeParseFile(packageDir.dopamineFile());

    Profile profile;

    if (profileName)
    {
        const filename = userProfileFile(profileName);
        enforce(exists(filename), format("Profile %s does not exist", profileName));
        profile = Profile.loadFromFile(filename);
        writeln("loading profile " ~ profile.name);
    }
    else
    {
        const filename = packageDir.profileFile();
        enforce(exists(filename), "Profile not selected");
        profile = Profile.loadFromFile(filename);
        writeln("loading profile " ~ profile.name);
    }

    assert(profile);

    const dirs = packageDir.profileDirs(profile);
    const archiveFile = packageDir.archiveFile(profile, recipe);

    if (exists(archiveFile))
    {
        writeln("warning: removing existing archive: ", archiveFile);
        remove(archiveFile);
    }

    ArchiveBackend.get.create(dirs.install, archiveFile);

    return 0;
}
