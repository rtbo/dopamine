module dopamine.state;

import dopamine.depdag;
import dopamine.deplock;
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

struct FlagState
{
    bool valid;
    string dir;

    this(bool valid, string dir = null)
    {
        this.valid = valid;
        this.dir = dir;
    }

    this(string dir)
    {
        this.valid = true;
        this.dir = dir;
    }

    bool opCast(T : bool)() const
    {
        return valid;
    }
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

/// Check if the build was successfully completed for the given [ProfileDirs]
FlagState checkBuildReady(PackageDir dir, ProfileDirs pdirs)
{
    return checkFlagState(dir, pdirs.buildFlag());
}

/// Check if a lock-file exists and is up-to-date for package in [dir]
/// Returns: the DAG loaded from the lock-file, or null
DepDAG checkLoadLockFile(PackageDir dir)
{
    const lf = dir.lockFile;

    if (!exists(lf))
        return DepDAG.init;

    if (timeLastModified(dir.dopamineFile) >= timeLastModified(lf))
        return DepDAG.init;

    return dagFromLockFile(lf);
}

FlagState checkDepInstalled(PackageDir dir, ProfileDirs pdirs)
{
    return checkFlagState(dir, pdirs.depsFlag());
}

private FlagState checkFlagState(PackageDir pdir, FlagFile flg)
{
    import std.string : strip;

    if (!flg.exists)
        return FlagState(false);

    const dir = flg.read().strip("\r\n");
    if (dir.length && (!dir.exists || !dir.isDir))
        return FlagState(false);

    if (flg.timeLastModified < pdir.dopamineFile.timeLastModified)
        return FlagState(false);

    return FlagState(dir);
}
