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
import std.file;
import std.format;
import std.getopt;
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
        d.userData = null;
    }
    return depInfos;
}

DepInfo[string] buildDependencies(DepDAG dag, Recipe recipe, Profile profile,
        DependencyCache depcache)
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
        auto pdirs = ddir.profileDirs(dprof);
        if (!checkBuildReady(ddir, pdirs))
        {
            auto depInfos = collectDepInfos(node);

            auto srcFlag = ddir.sourceFlag.absolute();
            auto bldFlag = pdirs.buildFlag.absolute();

            const depName = format("%s-%s", node.pack.name, node.ver);

            logInfo("Building %s", info(depName));
            ddir.dir.fromDir!({
                const src = drec.source();
                srcFlag.write(src);
                const bd = BuildDirs(src, pdirs.install);
                pdirs.install = drec.build(bd, dprof, depInfos).absolutePath();
                if (!exists(pdirs.install) && !isDir(pdirs.install))
                {
                    throw new FormatLogException("%s: %s built successfully but did not return the build directory",
                        error("Error"), info(depName));
                }
                logInfo("%s: %s - %s", info(depName), success("OK"), pdirs.install);
                bldFlag.write(pdirs.install);
            });
        }
        else
        {
            logVerbose("%s: Already up-to-date", info(format("%s-%s", node.pack.name, node.ver)));
        }
        node.userData = new DepInfoObj(pdirs.install);
    }

    return collectDepInfos(dag.root.resolvedNode);
}

int depInstallMain(string[] args)
{
    string profileName;
    bool noNetwork;

    auto helpInfo = getopt(args, "profile|p", &profileName, "no-network|N", &noNetwork);

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

    const network = noNetwork ? No.network : Yes.network;
    auto depcache = new DependencyCache(network);
    scope (exit)
        depcache.dispose();

    auto dag = enforce(checkLoadLockFile(dir), new FormatLogException(
            "%s: Dependencies are not locked. run %s.", error("Error"), info("dop deplock")));

    enforce(dagIsResolved(dag), new FormatLogException("%s: Dependencies not properly locked. Try to run %s",
            error("Error"), info("dop deplock --force")));

    auto profile = enforceProfileReady(dir, recipe, profileName);

    buildDependencies(dag, recipe, profile, depcache);

    logInfo("%s: %s", info("Dependencies"), success("OK"));

    return 0;
}
