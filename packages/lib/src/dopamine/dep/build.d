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
        const name = depNode.name.name;
        auto service = depNode.dub ? services.dub : services.dop;
        auto rdir = service.packRecipe(name, depNode.aver, depNode.revision);
        const prof = profile.subset(rdir.recipe.tools);
        auto opts = options.forDependency(name).union_(depNode.options);
        const conf = BuildConfig(prof, opts);
        auto depInfos = collectDirectDepBuildInfos(depNode);
        const buildId = BuildId(rdir.recipe, conf, depInfos, stageDest);
        const bPaths = rdir.buildPaths(buildId);

        depNode.buildInfo = DepBuildInfo(name, depNode.dub, depNode.ver, buildId, bPaths.install);
    }
}

DepBuildInfo[] collectDirectDepBuildInfos(DagNode node)
in (!node || node.isResolved, node ? node.name ~ " isn't resolved" : "node is null")
{
    if (!node)
        return null;

    DepBuildInfo[] res;
    foreach(de; node.downEdges)
    {
        auto dbi = enforce(de.down.resolvedNode).buildInfo;
        enforce(!dbi.isNull, "No build info for dependency " ~ de.down.name);
        res ~= dbi.get;
    }
    return res;
}

DepBuildInfo[string] collectDepBuildInfos(DagNode node)
in (!node || node.isResolved, node ? node.name ~ " isn't resolved" : "node is null")
{
    if (!node)
        return null;

    DepBuildInfo[string] res;
    foreach (k, v; node.collectDependencies())
    {
        if (v.location.isSystem)
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
        if (depNode.location.isSystem)
            continue;

        auto service = depNode.dub ? services.dub : services.dop;

        const pkgName = depNode.name;
        const isModule = pkgName.isModule;

        // FIXME: module batch building
        const mods = isModule ? [pkgName.modName] : null;

        auto rdir = service.packRecipe(pkgName.pkgName, depNode.aver, depNode.revision);
        const prof = profile.subset(rdir.recipe.tools);
        auto opts = options.forDependency(pkgName.name).union_(depNode.options);
        foreach (c; depNode.optionConflicts)
        {
            enforce(
                c in opts,
                new ErrorLogException(
                    "Unresolved option conflict for dependency %s: %s.\n" ~
                    "Ensure to set the option %s with the `%s` command.",
                    info(pkgName.name), color(Color.magenta, c),
                    color(Color.cyan | Color.bright, pkgName.name ~ "/" ~ c),
                    info("dop options")
                )
            );
        }
        const conf = BuildConfig(prof, mods, opts);
        auto depInfos = collectDirectDepBuildInfos(depNode);
        const bid = BuildId(rdir.recipe, conf, depInfos, stageDest);
        const bPaths = rdir.buildPaths(bid);

        const packHumanName = format("%s-%s", pkgName.name, depNode.ver);
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
        if (isModule)
            srcDir = buildPath(srcDir, rdir.recipe.moduleSourceDir(pkgName.modName));

        srcDir = buildNormalizedPath(absolutePath(srcDir, rdir.root));
        enforce(exists(srcDir) && isDir(srcDir), "No such source directory: " ~ srcDir);

        if (!rdir.checkBuildReady(bid, reason))
        {
            logInfo("%s: Building   (ID: %s)", info(packNameHead), color(Color.cyan, bid));
            mkdirRecurse(bPaths.build);

            auto di = collectDepBuildInfos(depNode);
            const bd = BuildDirs(rdir.root, srcDir, bPaths.build, stageDest ? stageDest : bPaths.install);
            auto state = bPaths.stateFile.read();

            if (isModule)
                rdir.recipe.buildModule(bd, conf, di);
            else
                rdir.recipe.build(bd, conf, di);

            state.buildTime = Clock.currTime;
            bPaths.stateFile.write(state);
        }
        else
        {
            logInfo("%s: Up-to-date (ID: %s)", info(packNameHead), color(Color.cyan, bid));
        }

        depNode.buildInfo = DepBuildInfo(pkgName.name, depNode.dub, depNode.ver, bid, bPaths.install);
    }

    return collectDepBuildInfos(dag.root.resolvedNode);
}

private string[] collectTools(DepDAG dag, DepServices services)
{
    import std.algorithm : canFind, sort;

    string[] allTools;

    foreach (depNode; dag.traverseTopDownResolved)
    {
        if (depNode.location.isSystem)
            continue;

        auto service = depNode.dub ? services.dub : services.dop;
        auto drdir = service.getPackOrModuleRecipe(depNode.name, depNode.aver, depNode.revision);
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
