module dopamine.dep.build;

import dopamine.build_id;
import dopamine.dep.dag;
import dopamine.dep.service;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.state;

import std.exception;
import std.file;
import std.path;

DepInfo[string] collectDepInfos(DepDAG dag, Recipe recipe,
    const(Profile) profile, DepService service, string stageFalseDest=null)
in (dag.resolved)
{
    const langs = collectLangs(dag, service);
    enforceHasLangs(profile, langs, recipe);

    foreach (depNode; dag.traverseTopDownResolved())
    {
        auto rec = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        auto rdir = RecipeDir.enforced(dirName(rec.filename));
        auto prof = profile.subset(rec.langs);
        auto conf = BuildConfig(prof);
        if (rec.stageFalse && stageFalseDest)
        {
            conf.stageFalseDest = stageFalseDest;
        }
        auto cdirs = rdir.configDirs(conf);

        depNode.userData = new DepInfoObj(cdirs.installDir);
    }

    return collectNodeDepInfos(dag.root.resolvedNode);
}

DepInfo[string] buildDependencies(DepDAG dag, Recipe recipe,
    const(Profile) profile, DepService service, string stageFalseDest=null)
in (dag.resolved)
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
        auto rec = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        auto rdir = RecipeDir.enforced(dirName(rec.filename));
        auto prof = profile.subset(rec.langs);
        auto conf = BuildConfig(prof);
        if (rec.stageFalse && stageFalseDest)
        {
            conf.stageFalseDest = stageFalseDest;
        }
        auto cdirs = rdir.configDirs(conf);

        const packHumanName = format("%s-%s", depNode.pack.name, depNode.ver);
        const packNameHead = format("%*s", maxLen, packHumanName);

        chdir(rdir.dir);

        string reason;
        auto srcDir = checkSourceReady(rdir, rec, reason);
        if (!srcDir)
        {
            logInfo("%s: Fetching source code", info(packNameHead));
            auto state = rdir.stateFile.read();
            srcDir = state.srcDir = rec.source();
            rdir.stateFile.write(state);
        }
        assert(srcDir && exists(srcDir));

        srcDir = absolutePath(srcDir, rdir.dir);

        if (!checkBuildReady(rdir, cdirs, reason))
        {
            logInfo("%s: Building", info(packNameHead));
            mkdirRecurse(cdirs.buildDir);

            auto depInfos = collectNodeDepInfos(depNode);
            const bd = BuildDirs(rdir.dir, srcDir, cdirs.installDir);
            auto state = cdirs.stateFile.read();

            chdir(cdirs.buildDir);
            rec.build(bd, conf, depInfos);

            state.buildTime = Clock.currTime;
            cdirs.stateFile.write(state);
        }
        else
        {
            logInfo("%s: Up-to-date", info(packNameHead));
        }

        depNode.userData = new DepInfoObj(cdirs.installDir);
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
        auto drec = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        foreach (l; drec.langs)
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
