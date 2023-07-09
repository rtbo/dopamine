module dopamine.dep.build;

import dopamine.build_id;
import dopamine.dep.resolve;
import dopamine.dep.service;
import dopamine.log;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.exception;
import std.file;
import std.path;
import std.range;

DepGraphBuildInfo calcDepBuildInfos(
    DepGraph dag,
    Recipe recipe,
    const(Profile) profile,
    DepServices services,
    OptionSet options,
    string stageDest = null)
in (!stageDest || isAbsolute(stageDest))
{
    const tools = collectTools(dag, services);
    enforceHasTools(profile, tools, recipe);

    DepGraphBuildInfo res;

    foreach (const(DgNode) depNode; dag.traverseBottomUp())
    {
        const name = depNode.name;
        const kind = depNode.kind;

        auto service = services[depNode.kind];
        auto rdir = service.packRecipe(name, depNode.aver, depNode.revision);
        const prof = profile.subset(rdir.recipe.tools);
        auto opts = options.forDependency(name).union_(depNode.options);
        const conf = BuildConfig(prof, opts);
        auto depInfos = res.nodeDirectDepBuildInfos(depNode);
        const buildId = BuildId(rdir.recipe, conf, depInfos, stageDest);
        const bPaths = rdir.buildPaths(buildId);

        res[kind, name] = DepBuildInfo(name, depNode.kind, depNode.ver, buildId, bPaths.install);
    }

    return res;
}

DepGraphBuildInfo nodeDeepDepBuildInfos(DepGraphBuildInfo dgbi, const(DgNode) node)
{
    if (!node)
        return DepGraphBuildInfo.init;

    DepGraphBuildInfo res;

    foreach (dep; dgTraverseTopDown(node, No.root))
    {
        if (dep.location.isSystem)
            continue;

        auto dbi = enforce(
            dep.name in dgbi[dep.kind],
            "No bbuild info for dependency " ~ dep.name);

        res[dep.kind, dep.name] = *dbi;
    }

    return res;
}

DepBuildInfo[] nodeDirectDepBuildInfos(DepGraphBuildInfo dgbi, const(DgNode) node)
{
    if (!node)
        return null;

    DepBuildInfo[] res;
    foreach (de; node.downEdges)
    {
        auto dbi = enforce(
            de.down.name in dgbi[de.down.kind],
            "No build info for dependency " ~ de.down.name);
        res ~= *dbi;
    }
    return res;
}

DepGraphBuildInfo buildDependencies(
    DepGraph dag,
    Recipe recipe,
    const(Profile) profile,
    DepServices services,
    OptionSet options,
    string stageDest = null)
in (!stageDest || isAbsolute(stageDest))
{
    import std.algorithm : map, maxElement;
    import std.datetime : Clock;
    import std.format : format;

    const tools = collectTools(dag, services);
    enforceHasTools(profile, tools, recipe);

    const maxLen = dag.traverseTopDown()
        .map!(dn => dn.name.length + dn.ver.toString().length + 1)
        .chain(only(0)) // in case of empty deps
        .maxElement();

    DepGraphBuildInfo res;

    foreach (depNode; dag.traverseBottomUp())
    {
        if (depNode.location.isSystem)
            continue;

        auto service = services[depNode.kind];

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
        auto depInfos = res.nodeDirectDepBuildInfos(depNode);
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

            auto di = res.nodeDeepDepBuildInfos(depNode);
            const bd = BuildDirs(rdir.root, srcDir, bPaths.build, stageDest ? stageDest
                    : bPaths.install);
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

        logInfo("Adding %s dep %s", depNode.kind, depNode.name);

        res[depNode.kind, depNode.name] = DepBuildInfo(pkgName.name, depNode.kind, depNode.ver, bid, bPaths
                .install);
    }

    return res;
}

private string[] collectTools(DepGraph dag, DepServices services)
{
    import std.algorithm : canFind, sort;

    string[] allTools;

    foreach (depNode; dag.traverseTopDown)
    {
        if (depNode.location.isSystem)
            continue;

        auto service = services[depNode.kind];
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
        string msg = format("Profile %s misses the following tools to build the dependencies of %s-%s:", profile
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
