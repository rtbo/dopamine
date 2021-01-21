module dopamine.client.cache;

import dopamine.client.build;
import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.semver;

import std.exception;
import std.file;
import std.format;
import std.getopt;

void enforceCanBeCached(Recipe recipe)
{
    enforce(recipe.name, new FormatLogException(
            "%s: recipe can't be cached or exported: it has no name", error("Error")));
    enforce(recipe.ver != Semver.init, new FormatLogException(
            "%s: recipe can't be cached or exported: it defines no proper version", error("Error")));
    enforce(recipe.revision(), new FormatLogException(
            "%s: recipe can't be cached or exported: it do not define a revision", error("Error")));
}

int cacheMain(string[] args)
{
    string profileName;

    auto helpInfo = getopt(args, "profile|p", &profileName);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop cache command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);

    auto profile = enforceProfileReady(dir, recipe, profileName);
    const profileDirs = dir.profileDirs(profile);

    try
    {
        enforceBuildReady(dir, profileDirs);
    }
    catch (FormatLogException ex)
    {
        ex.log();
        logError(
                "The package must be known to build with at least one profile before being cached or exported");
        return 1;
    }

    enforceCanBeCached(recipe);

    const depDir = cacheDepDir(recipe);
    auto flag = cacheDepDirFlag(recipe);

    mkdirRecurse(depDir.dir);
    copy(dir.dopamineFile(), depDir.dopamineFile());
    flag.touch();

    logInfo("%s is now cached at %s.\nYou may use it as a dependency. Consider %s allow others to use it.",
            info(format("%s-%s", recipe.name, recipe.ver)), info(depDir.dir), info("dop publish"));

    return 0;
}
