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

void ensureDepBuildInfos(
    DepDAG dag,
    Recipe recipe,
    const(Profile) profile,
    DepServices services,
    OptionSet options,
    string stageDest=null)
in (dag.resolved)
in (!stageDest || isAbsolute(stageDest))
{
    const tools = collectTools(dag, services);
    enforceHasTools(profile, tools, recipe);

    foreach (DagNode depNode; dag.traverseBottomUpResolved())
    {
        auto service = depNode.dub ? services.dub : services.dop;
        auto rdir = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        const prof = profile.subset(rdir.recipe.tools);
        auto opts = options.forDependency(depNode.name).union_(depNode.options);
        const conf = BuildConfig(prof, opts);
        auto depInfos = collectDirectDepBuildInfos(depNode);
        const buildId = BuildId(rdir.recipe, conf, depInfos, stageDest);
        const bPaths = rdir.buildPaths(buildId);

        depNode.buildInfo = DepBuildInfo(depNode.name, depNode.dub, depNode.ver, buildId, bPaths.install);
    }
}

DepBuildInfo[] collectDirectDepBuildInfos(DagNode node)
in (!node || node.isResolved)
{
    if (!node)
        return null;

    DepBuildInfo[] res;
    foreach(de; node.downEdges)
    {
        auto dbi = enforce(de.down.resolvedNode).buildInfo;
        enforce(!dbi.isNull);
        res ~= dbi.get;
    }
    return res;
}

DepBuildInfo[string] collectDepBuildInfos(DagNode node)
in (!node || node.isResolved)
{
    if (!node)
        return null;

    DepBuildInfo[string] res;
    foreach (k, v; node.collectDependencies())
    {
        if (v.location == DepLocation.system)
            continue;

        assert(!v.buildInfo.isNull);
        res[k] = v.buildInfo.get;
    }
    return res;
}

DepBuildInfo[string] buildDependencies(
    DepDAG dag,
    Recipe recipe,
    const(Profile) profile,
    DepServices services,
    OptionSet options,
    string stageDest=null)
in (dag.resolved)
in (!stageDest || isAbsolute(stageDest))
{
    import std.algorithm : map, maxElement;
    import std.datetime : Clock;
    import std.format : format;

    const tools = collectTools(dag, services);
    enforceHasTools(profile, tools, recipe);

    const maxLen = dag.traverseTopDownResolved()
        .map!(dn => dn.pack.name.length + dn.ver.toString().length + 1)
        .maxElement();


    foreach (depNode; dag.traverseBottomUpResolved())
    {
        if (depNode.location == DepLocation.system)
            continue;

        auto service = depNode.dub ? services.dub : services.dop;
        auto rdir = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        const prof = profile.subset(rdir.recipe.tools);
        auto opts = options.forDependency(depNode.name).union_(depNode.options);
        foreach (c; depNode.optionConflicts)
        {
            enforce(
                c in opts,
                new ErrorLogException(
                    "Unresolved option conflict for dependency %s: %s.\n" ~
                    "Ensure to set the option %s with the `%s` command.",
                    info(depNode.name), color(Color.magenta, c),
                    color(Color.cyan | Color.bright, depNode.name ~ "/" ~ c),
                    info("dop options")
                )
            );
        }
        const conf = BuildConfig(prof, opts);
        auto depInfos = collectDirectDepBuildInfos(depNode);
        const bid = BuildId(rdir.recipe, conf, depInfos, stageDest);
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
        enforce(srcDir, "recipe did not return the source code location");
        srcDir = absolutePath(srcDir, rdir.root);
        enforce(exists(srcDir) && isDir(srcDir), "No such source directory: " ~ srcDir);

        if (!rdir.checkBuildReady(bid, reason))
        {
            logInfo("%s: Building", info(packNameHead));
            mkdirRecurse(bPaths.build);

            auto di = collectDepBuildInfos(depNode);
            const bd = BuildDirs(rdir.root, srcDir, bPaths.build, stageDest ? stageDest : bPaths.install);
            auto state = bPaths.stateFile.read();

            rdir.recipe.build(bd, conf, di);

            state.buildTime = Clock.currTime;
            bPaths.stateFile.write(state);
        }
        else
        {
            logInfo("%s: Up-to-date", info(packNameHead));
        }

        depNode.buildInfo = DepBuildInfo(depNode.name, depNode.dub, depNode.ver, bid, bPaths.install);
    }

    return collectDepBuildInfos(dag.root.resolvedNode);
}

private string[] collectTools(DepDAG dag, DepServices services)
{
    import std.algorithm : canFind, sort;

    string[] allTools;

    foreach (depNode; dag.traverseTopDownResolved)
    {
        if (depNode.location == DepLocation.system)
            continue;

        auto service = depNode.dub ? services.dub : services.dop;
        auto drdir = service.packRecipe(depNode.pack.name, depNode.aver, depNode.revision);
        foreach (t; drdir.recipe.tools)
        {
            if (!allTools.canFind(t))
                allTools ~= t;
        }
    }

    sort(allTools);

    return allTools;
}

private void enforceHasTools(const(Profile) profile, const(string)[] tools, Recipe recipe)
{
    import std.format : format;

    if (!profile.hasAllTools(tools))
    {
        string msg = format("Profile %s misses the following languages to build the dependencies of %s-%s:", profile
                .name, recipe.name, recipe.ver);
        foreach (t; tools)
        {
            if (!profile.hasTool(t))
            {
                msg ~= "\n  - " ~ t;
            }
        }
        throw new Exception(msg);
    }
}
