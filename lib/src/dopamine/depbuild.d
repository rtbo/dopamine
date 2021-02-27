module dopamine.depbuild;

import dopamine.depdag;
import dopamine.dependency;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.util;
import dopamine.state;

import std.exception;
import std.file;
import std.format;

DepInfo[string] buildDependencies(DepDAG dag, Recipe recipe,
        const(Profile) profile, CacheRepo depcache, string stageDest = null)
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
        const depName = format("%s-%s", node.pack.name, node.ver);

        logVerbose("Traversing dependency %s", info(depName));

        auto drec = depcache.packRecipe(node.pack.name, node.ver, node.revision);
        const ddir = depcache.packDir(drec);
        auto dprof = profile.subset(drec.langs);
        const pdirs = ddir.profileDirs(dprof);
        auto depInfos = collectDepInfos(node);

        scope (success)
            logInfo("%s: %s - %s", info(depName), success("OK"), pdirs.install);

        auto srcFlag = ddir.sourceFlag.absolute();
        auto bldFlag = pdirs.buildFlag.absolute();

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
                    throw new FormatLogException("%s: %s reported to install but the install directory does not exist",
                        error("Error"), info(depName));
                }
                else if (!inst && !drec.hasPackFunc)
                {
                    throw new FormatLogException("%s: %s build function did not install and has no package function",
                        error("Error"), info(depName));
                }
                bldFlag.write(inst ? pdirs.install : "");
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
