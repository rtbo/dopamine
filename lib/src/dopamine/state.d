module dopamine.state;

import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.util;

import std.file;

/// Check if a profile file exists in [dir]
/// Returns: the Profile loaded from the package, or null
Profile checkProfileFile(PackageDir dir)
{
    const pf = dir.profileFile();

    if (!exists(pf))
        return null;

    return Profile.loadFromFile(pf);
}

/// Check if a profile named [name] exists, and load it
Profile checkProfileName(PackageDir dir, Recipe recipe, string name = "default",
        bool saveToDir = false, string* pname = null)
{
    auto pf = userProfileFile(name);
    if (!exists(pf))
    {
        const langs = recipe.langs;
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
string checkSourceReady(PackageDir dir, Recipe recipe)
{
    if (recipe.inTreeSrc)
    {
        return recipe.source();
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

private string checkFlagFile(PackageDir dir, FlagFile flag, FlagFile previous)
{
    if (!flag.exists() || !previous.exists())
        return null;

    const tlm = flag.timeLastModified;

    if (tlm < previous.timeLastModified || tlm < timeLastModified(dir.dopamineFile))
        return null;

    return flag.read();
}

/// Check if the build was successfully completed for the given [ProfileDirs]
string checkBuildReady(PackageDir dir, ProfileDirs pdirs)
{
    return checkFlagFile(dir, pdirs.buildFlag, dir.sourceFlag);
}
