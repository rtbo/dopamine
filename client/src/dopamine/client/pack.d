module dopamine.client.pack;

import dopamine.build_id;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;

import dopamine.client.build;
import dopamine.client.profile;
import dopamine.client.resolve;
import dopamine.client.source;
import dopamine.client.utils;

import std.file;
import std.getopt;
import std.path;

int packageMain(string[] args)
{
    string profileName;

    // dfmt off
    auto helpInfo = getopt(args,
        "profile|p",    &profileName,
    );
    // dfmt on

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop package command", helpInfo.options);
        return 0;
    }

    string dest = args.length <= 1 ? null : args[1];

    const rdir = RecipeDir.enforced(".");
    auto lock = acquireRecipeLockFile(rdir);

    auto recipe = parseRecipe(rdir);

    auto srcDir = enforceSourceReady(rdir, recipe);
    auto profile = enforceProfileReady(rdir, recipe, profileName);

    DepInfo[string] depInfos;
    if (recipe.hasDependencies)
    {
        auto dag = enforceResolved(rdir);
        foreach (dep; dag.traverseBottomUpResolved)
        {
            // build if not done
            // collect DepInfo
        }
    }

    auto config = BuildConfig(profile);

    const cdirs = rdir.configDirs(config);
    auto cLock = acquireConfigLockFile(cdirs);

    enforceBuildReady(rdir, cdirs);

    if (!dest)
        dest = cdirs.defaultPackageDir;

    const cwd = getcwd();
    const root = absolutePath(".", cwd);
    const src = absolutePath(srcDir, cwd);
    const pdirs = PackageDirs(root, src, cdirs.buildDir);

    mkdirRecurse(dest);

    {
        chdir(dest);
        scope(success)
            chdir(cwd);

        recipe.pack(pdirs, config, depInfos);
    }

    logInfo("Package: %s - %s", success("OK"), info(relativePath(dest, cwd)));

    return 0;
}
