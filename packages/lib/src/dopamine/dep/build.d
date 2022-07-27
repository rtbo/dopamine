module dopamine.dep.build;

import dopamine.build_id;
import dopamine.dep.dag;
import dopamine.dep.service;
import dopamine.log;
import dopamine.profile;
import dopamine.recipe;
import dopamine.state;

import std.exception;
import std.file;
import std.path;

DepInfo[string] collectDepInfos(DepDAG dag, Recipe recipe,
    const(Profile) profile, DepService service, string stageDest=null)
in (dag.resolved)
in (!stageDest || isAbsolute(stageDest))
{
    const langs = collectLangs(dag, service);
    enforceHasLangs(profile, langs, recipe);

    foreach (depNode; dag.traverseTopDownResolved())
    {
        auto rdir = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        const prof = profile.subset(rdir.recipe.langs);
        const conf = BuildConfig(prof);
        const buildId = BuildId(rdir.recipe, conf, stageDest);
        const bPaths = rdir.buildPaths(buildId);

        depNode.userData = new DepInfoObj(bPaths.install);
    }

    return collectNodeDepInfos(dag.root.resolvedNode);
}

DepInfo[string] buildDependencies(DepDAG dag, Recipe recipe,
    const(Profile) profile, DepService service, string stageDest=null)
in (dag.resolved)
in (!stageDest || isAbsolute(stageDest))
{
    import std.algorithm : map, maxElement;
    import std.datetime : Clock;
    import std.format : format;

    const langs = collectLangs(dag, service);
    enforceHasLangs(profile, langs, recipe);

    const maxLen = dag.traverseTopDownResolved()
        .map!(dn => dn.pack.name.length + dn.ver.toString().length + 1)
        .maxElement();

    const cwd = getcwd();
    scope(exit)
        chdir(cwd);

    foreach (depNode; dag.traverseBottomUpResolved())
    {
        if (depNode.location == DepLocation.system)
            continue;

        auto rdir = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        const prof = profile.subset(rdir.recipe.langs);
        const conf = BuildConfig(prof);
        const bid = BuildId(rdir.recipe, conf, stageDest);
        const bPaths = rdir.buildPaths(bid);

        const packHumanName = format("%s-%s", depNode.pack.name, depNode.ver);
        const packNameHead = format("%*s", maxLen, packHumanName);

        chdir(rdir.root);

        mkdirRecurse(rdir.dopPath());

        string reason;
        auto srcDir = checkSourceReady(rdir, rdir.recipe, reason);
        if (!srcDir)
        {
            logInfo("%s: Fetching source code", info(packNameHead));
            auto state = rdir.stateFile.read();
            srcDir = state.srcDir = rdir.recipe.source();
            rdir.stateFile.write(state);
        }
        assert(srcDir && exists(srcDir));

        srcDir = absolutePath(srcDir, rdir.root);

        if (!checkBuildReady(rdir, bPaths, reason))
        {
            logInfo("%s: Building", info(packNameHead));
            mkdirRecurse(bPaths.build);

            auto depInfos = collectNodeDepInfos(depNode);
            const bd = BuildDirs(rdir.root, srcDir, stageDest ? stageDest : bPaths.install);
            auto state = bPaths.stateFile.read();

            chdir(bPaths.build);
            rdir.recipe.build(bd, conf, depInfos);

            state.buildTime = Clock.currTime;
            bPaths.stateFile.write(state);
        }
        else
        {
            logInfo("%s: Up-to-date", info(packNameHead));
        }

        depNode.userData = new DepInfoObj(bPaths.install);
    }

    return collectNodeDepInfos(dag.root.resolvedNode);
}

private class DepInfoObj
{
    this(string installDir)
    {
        info = DepInfo(installDir);
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

private Lang[] collectLangs(DepDAG dag, DepService service)
{
    import std.algorithm : canFind, sort;

    Lang[] allLangs;

    foreach (depNode; dag.traverseTopDownResolved)
    {
        if (depNode.location == DepLocation.system)
            continue;

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
