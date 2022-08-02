module dopamine.dep.build;

import dopamine.build_id;
import dopamine.dep.dag;
import dopamine.dep.service;
import dopamine.log;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.exception;
import std.file;
import std.path;

DepInfo[string] collectDepInfos(DepDAG dag, Recipe recipe,
    const(Profile) profile, DepServices services, string stageDest=null)
in (dag.resolved)
in (!stageDest || isAbsolute(stageDest))
{
    const langs = collectLangs(dag, services);
    enforceHasLangs(profile, langs, recipe);

    foreach (depNode; dag.traverseTopDownResolved())
    {
        auto service = depNode.dub ? services.dub : services.dop;
        auto rdir = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        const prof = profile.subset(rdir.recipe.langs);
        const conf = BuildConfig(prof);
        const buildId = BuildId(rdir.recipe, conf, stageDest);
        const bPaths = rdir.buildPaths(buildId);

        depNode.userData = new DepInfoObj(bPaths.install, depNode.ver);
    }

    return collectNodeDepInfos(dag.root.resolvedNode);
}

DepInfo[string] buildDependencies(DepDAG dag, Recipe recipe,
    const(Profile) profile, DepServices services, string stageDest=null)
in (dag.resolved)
in (!stageDest || isAbsolute(stageDest))
{
    import std.algorithm : map, maxElement;
    import std.datetime : Clock;
    import std.format : format;

    const langs = collectLangs(dag, services);
    enforceHasLangs(profile, langs, recipe);

    const maxLen = dag.traverseTopDownResolved()
        .map!(dn => dn.pack.name.length + dn.ver.toString().length + 1)
        .maxElement();

    foreach (depNode; dag.traverseBottomUpResolved())
    {
        if (depNode.location == DepLocation.system)
            continue;

        auto service = depNode.dub ? services.dub : services.dop;
        auto rdir = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        const prof = profile.subset(rdir.recipe.langs);
        const conf = BuildConfig(prof);
        const bid = BuildId(rdir.recipe, conf, stageDest);
        const bPaths = rdir.buildPaths(bid);

        const packHumanName = format("%s-%s", depNode.pack.name, depNode.ver);
        const packNameHead = format("%*s", maxLen, packHumanName);

        mkdirRecurse(rdir.dopPath());

        string reason;
        auto srcDir = rdir.checkSourceReady(reason);
        if (!srcDir)
        {
            logInfo("%s: Fetching source code", info(packNameHead));
            auto state = rdir.stateFile.read();
            srcDir = state.srcDir = rdir.recipe.source();
            rdir.stateFile.write(state);
        }
        assert(srcDir && exists(srcDir));

        srcDir = absolutePath(srcDir, rdir.root);

        if (!rdir.checkBuildReady(bid, reason))
        {
            logInfo("%s: Building", info(packNameHead));
            mkdirRecurse(bPaths.build);

            auto depInfos = collectNodeDepInfos(depNode);
            const bd = BuildDirs(rdir.root, srcDir, bPaths.build, stageDest ? stageDest : bPaths.install);
            auto state = bPaths.stateFile.read();

            rdir.recipe.build(bd, conf, depInfos);

            state.buildTime = Clock.currTime;
            bPaths.stateFile.write(state);
        }
        else
        {
            logInfo("%s: Up-to-date", info(packNameHead));
        }

        depNode.userData = new DepInfoObj(bPaths.install, depNode.ver);
    }

    return collectNodeDepInfos(dag.root.resolvedNode);
}

private class DepInfoObj
{
    this(string installDir, Semver ver)
    {
        info = DepInfo(installDir, ver);
    }

    DepInfo info;
}

private DepInfo[string] collectNodeDepInfos(DagNode node)
in (node.isResolved)
{
    DepInfo[string] res;
    foreach (k, v; node.collectDependencies())
    {
        if (v.location == DepLocation.system)
            continue;

        auto obj = cast(DepInfoObj)v.userData;
        assert(obj);
        res[k] = obj.info;
    }
    return res;
}

private Lang[] collectLangs(DepDAG dag, DepServices services)
{
    import std.algorithm : canFind, sort;

    Lang[] allLangs;

    foreach (depNode; dag.traverseTopDownResolved)
    {
        if (depNode.location == DepLocation.system)
            continue;

        auto service = depNode.dub ? services.dub : services.dop;
        auto drdir = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        foreach (l; drdir.recipe.langs)
        {
            if (!allLangs.canFind(l))
                allLangs ~= l;
        }
    }

    sort(allLangs);

    return allLangs;
}

private void enforceHasLangs(const(Profile) profile, const(Lang)[] langs, Recipe recipe)
{
    import std.format : format;

    if (!profile.hasAllLangs(langs))
    {
        string msg = format("Profile %s misses the following languages to build the dependencies of %s-%s:", profile
                .name, recipe.name, recipe.ver);
        foreach (l; langs)
        {
            if (!profile.hasLang(l))
            {
                msg ~= "\n  - " ~ l.to!string;
            }
        }
        throw new Exception(msg);
    }
}
