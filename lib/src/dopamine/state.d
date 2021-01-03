/// This module implements a kind of Directed Acyclic Graph
/// that ensures that necessary state is reached for each of
/// the packaging steps.
module dopamine.state;

import dopamine.archive;
import dopamine.build;
import dopamine.depcache;
import dopamine.depdag;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.source;
import dopamine.util;

import std.exception;
import std.file;
import std.typecons;

/// Check if a lock-file exists and is up-to-date for package in [dir]
/// Returns: true if lock-file exists and is up-to-date, false otherwise.
bool checkLockFile(PackageDir dir)
{
    const lf = dir.lockFile;

    if (!exists(lf))
        return false;

    return timeLastModified(dir.dopamineFile) < timeLastModified(lf);
}

/// Check if a lock-file exists and is up-to-date for package in [dir]
/// Returns: the DAG loaded from the lock-file, or null
DepPack checkLoadLockFile(PackageDir dir)
{
    const lf = dir.lockFile;

    if (!exists(lf))
        return null;

    if (timeLastModified(dir.dopamineFile) >= timeLastModified(lf))
        return null;

    return dagFromLockFile(lf);
}

/// Check if a profile file exists and is up-to-date for package in [dir]
/// Returns: the Profile loaded from the package, or null
Profile checkProfileFile(PackageDir dir, const(Recipe) recipe)
{
    const pf = dir.profileFile();

    if (!exists(pf))
        return null;

    const tlm = timeLastModified(pf);

    if (recipe.dependencies && (!exists(dir.lockFile) || timeLastModified(dir.lockFile) >= tlm))
        return null;

    if (timeLastModified(dir.dopamineFile) >= tlm)
        return null;

    return Profile.loadFromFile(pf);
}

/// Check if a profile named [name] exists, and load it
Profile checkProfileName(PackageDir dir, DepPack depDag,
        string name = "default", bool saveToDir = false, string* pname=null)
in(dagIsResolved(depDag))
{
    auto pf = userProfileFile(name);
    if (!exists(pf))
    {
        const langs = depDag.resolvedNode.langs;
        name = profileName(name, langs);
        pf = userProfileFile(name);
        if (!exists(pf))
            return null;
    }

    auto profile = Profile.loadFromFile(pf);
    if (saveToDir)
    {
        profile.saveToFile(dir.profileFile(), true, true);
    }
    if (pname)
        *pname = name;
    return profile;
}

/// Check if the source code is ready and up-to-date for package in [dir]
/// Returns: the path to the source directory, or null
string checkSourceReady(PackageDir dir, const(Recipe) recipe)
{
    if (!recipe.outOfTree)
    {
        return dir.dir;
    }

    auto flagFile = dir.sourceFlag();

    if (!flagFile.exists())
        return null;

    const sourceDir = flagFile.read();
    if (!exists(sourceDir) || !isDir(sourceDir))
        return null;

    if (timeLastModified(dir.dopamineFile()) >= flagFile.timeLastModified)
        return null;

    return sourceDir;
}

private bool checkFlagFile(PackageDir dir, FlagFile flag, FlagFile previous)
{
    if (!flag.exists() || !previous.exists())
        return false;

    const tlm = flag.timeLastModified;

    return tlm > previous.timeLastModified && tlm > timeLastModified(dir.dopamineFile);
}

/// Check if the build was correctly configured for the given [ProfileDirs]
bool checkConfigReady(PackageDir dir, ProfileDirs pdirs)
{
    return checkFlagFile(dir, pdirs.configFlag, dir.sourceFlag);
}

/// Check if the build was successfully completed for the given [ProfileDirs]
bool checkBuildReady(PackageDir dir, ProfileDirs pdirs)
{
    return checkFlagFile(dir, pdirs.buildFlag, pdirs.configFlag);
}

/// Check if the build was installed for the given [ProfileDirs]
bool checkInstallReady(PackageDir dir, ProfileDirs pdirs)
{
    return checkFlagFile(dir, pdirs.installFlag, pdirs.buildFlag);
}

string checkArchiveReady(PackageDir dir, const(Recipe) recipe, Profile profile)
{
    const file = dir.archiveFile(profile, recipe);
    if (!exists(file))
        return null;

    const dirs = dir.profileDirs(profile);

    auto previous = dirs.installFlag;

    if (!previous.exists())
        return null;

    const tlm = timeLastModified(file);

    if (previous.timeLastModified >= tlm || timeLastModified(dir.dopamineFile()) >= tlm)
        return null;

    return file;
}
