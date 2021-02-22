module dopamine.client.depinstall;

import dopamine.client.profile;
import dopamine.client.recipe;
import dopamine.depcache;
import dopamine.depdag;
import dopamine.deplock;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.state;
import dopamine.util;

import std.exception;
import std.getopt;
import std.file;
import std.format;
import std.path;
import std.typecons;

private class DepInfoObj
{
    string installDir;
    this(string installDir)
    {
        this.installDir = installDir;
    }
}

private DepInfo[string] collectDepInfos(DepNode node)
{
    DepInfo[string] depInfos;
    auto deps = dagCollectDependencies(node);
    foreach (k, d; deps)
    {
        auto dio = cast(DepInfoObj) d.userData;
        depInfos[k] = DepInfo(dio.installDir);
    }
    return depInfos;
}

DepInfo[string] buildDependencies(DepDAG dag, Recipe recipe,
        const(Profile) profile, DependencyCache depcache, string stageDest = null)
in(dagIsResolved(dag))
{
    import std.path : absolutePath;

    if (dag.allLangs.length == 0)
    {
        dagFetchLanguages(dag, recipe, depcache);
    }

    enforce(!dag.allLangs.length || profile.hasAllLangs(dag.allLangs),
            new FormatLogException("%s: Profile %s do not have all needed languages to build dependencies",
                error("Error"), info(profile.name)));

    foreach (node; dag.traverseBottomUpResolved())
    {
        auto drec = depcache.packRecipe(node.pack.name, node.ver, node.revision);
        const ddir = cacheDepRevDir(node.pack.name, node.ver, node.revision);
        auto dprof = profile.subset(drec.langs);
        const pdirs = ddir.profileDirs(dprof);
        auto depInfos = collectDepInfos(node);

        auto srcFlag = ddir.sourceFlag.absolute();
        auto bldFlag = pdirs.buildFlag.absolute();

        const depName = format("%s-%s", node.pack.name, node.ver);

        ddir.dir.fromDir!({
            auto src = checkSourceReady(ddir, drec);
            if (!src)
            {
                src = drec.source();
                srcFlag.write(src);
            }

            const bd = pdirs.buildDirs(src);
            if (!checkBuildReady(ddir, pdirs))
            {
                logInfo("Building %s...", info(depName));
                const inst = drec.build(bd, dprof, depInfos);
                if (inst && (!exists(pdirs.install) || !isDir(pdirs.install)))
                {
                    throw new FormatLogException("%s: %s built successfully but did not return the build directory",
                        error("Error"), info(depName));
                }
                else if (!inst)
                {
                    throw new FormatLogException("%s: %s build function did not install and has no package function",
                        error("Error"), info(depName));
                }
                bldFlag.write(inst ? pdirs.install : "");
                logInfo("%s: %s - %s", info(depName), success("OK"), pdirs.install);
            }

            if (drec.hasPackFunc)
            {
                drec.pack(bd, dprof, stageDest ? stageDest : bd.install);
            }
            else if (stageDest)
            {
                installRecurse(pdirs.install, stageDest);
            }

            drec.patchInstall(dprof, bd.install);
        });
        node.userData = new DepInfoObj(stageDest ? stageDest : pdirs.install);
    }

    return collectDepInfos(dag.root.resolvedNode);
}

private string normalized(string path)
{
    return path.length ? buildNormalizedPath(absolutePath(path)) : null;
}

int depInstallMain(string[] args)
{
    string stageDest;
    string profileName;
    bool noNetwork;
    bool force;

    auto helpInfo = getopt(args, "stage", &stageDest, "profile|p",
            &profileName, "no-network|N", &noNetwork, "force|f", &force);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop depinstall command", helpInfo.options);
        return 0;
    }

    const dir = PackageDir.enforced(".");
    auto recipe = parseRecipe(dir);
    if (!recipe.hasDependencies)
    {
        logInfo("No dependencies. Nothing to do.");
        return 0;
    }

    const profile = enforceProfileReady(dir, recipe, profileName);
    const pdirs = dir.profileDirs(profile);

    const depState = checkDepInstalled(dir, pdirs);
    if (!force && depState && normalized(depState.dir) == normalized(stageDest))
    {
        if (stageDest)
            logInfo("%s: Already up-to-date at %s. Run with %s to overcome.",
                    info("Dependencies"), stageDest, info("--force"));
        else
            logInfo("%s: Already up-to-date. Run with %s to overcome.",
                    info("Dependencies"), info("--force"));
        return 0;
    }

    const network = noNetwork ? No.network : Yes.network;
    auto depcache = new DependencyCache(network);
    scope (exit)
        depcache.dispose();

    auto dag = enforce(checkLoadLockFile(dir), new FormatLogException(
            "%s: Dependencies are not locked. run %s.", error("Error"), info("dop deplock")));

    enforce(dagIsResolved(dag), new FormatLogException("%s: Dependencies not properly locked. Try to run %s",
            error("Error"), info("dop deplock --force")));

    buildDependencies(dag, recipe, profile, depcache, stageDest.absolutePath());

    dir.profileDirs(profile).depsFlag.write(stageDest);

    if (stageDest)
        logInfo("%s: %s - %s", info("Dependencies"), success("OK"), stageDest);
    else
        logInfo("%s: %s", info("Dependencies"), success("OK"));

    return 0;
}
