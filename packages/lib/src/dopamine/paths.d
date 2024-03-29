module dopamine.paths;

import dopamine.build_id;
import dopamine.log;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.file;
import std.format;
import std.path;

@safe:

string homeDopDir()
{
    import std.process : environment;

    const home = environment.get("DOP_HOME");
    if (home)
        return home;

    version (linux)
    {
        return buildPath(environment["HOME"], ".dopamine");
    }
    else version (Windows)
    {
        return buildPath(environment["LOCALAPPDATA"], "Dopamine");
    }
    else
    {
        static assert(false, "unsupported OS");
    }
}

string homeLuaScript()
{
    import dopamine.conf : DOP_BUILD_ID;

    return buildPath(homeDopDir(), format("dop-%s.lua", DOP_BUILD_ID));
}

string findDopLuaScript()
out (lua; exists(lua) && isFile(lua))
{
    debug
    {
        const dev = buildNormalizedPath(__FILE_FULL_PATH__.dirName.buildPath("lua", "dop.lua"));
        if (exists(dev))
            return dev;
    }
    const dist = thisExePath.dirName.dirName.buildPath("share", "dopamine", "dop.lua");
    if (exists(dist))
        return dist;

    const home = homeLuaScript();
    if (!exists(home))
    {
        logVerbose("creating %s", info(home));

        mkdirRecurse(dirName(home));
        const content = import("dop.lua");
        write(home, cast(const(ubyte)[]) content);
    }
    return home;
}

string homeProfilesDir()
{
    return buildPath(homeDopDir(), "profiles");
}

string homeProfileFile(string name)
{
    return buildPath(homeProfilesDir(), name ~ ".ini");
}

string homeProfileFile(Profile profile)
{
    return homeProfileFile(profile.name);
}

string userLoginFile()
{
    return buildPath(homeDopDir(), "login.json");
}

string homeCacheDir()
{
    return buildPath(homeDopDir(), "cache");
}

string homeDubCacheDir()
{
    return buildPath(homeDopDir(), "dub-cache");
}
