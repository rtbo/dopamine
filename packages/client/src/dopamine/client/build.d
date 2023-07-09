module dopamine.client.build;

import dopamine.client.profile;
import dopamine.client.resolve;
import dopamine.client.source;
import dopamine.client.utils;

import dopamine.build_id;
import dopamine.cache;
import dopamine.dep.build;
import dopamine.dep.resolve;
import dopamine.dep.service;
import dopamine.log;
import dopamine.paths;
import dopamine.recipe;
import dopamine.registry;

import std.datetime;
import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.process;
import std.typecons;

void enforceBuildReady(RecipeDir rdir, BuildId buildId)
{
    string reason;
    if (!rdir.checkBuildReady(buildId, reason))
    {
        throw new FormatLogException(
            "Build: %s - %s. Try to run %s.",
            error("NOK"), reason, info("dop build")
        );
    }

    logInfo("%s: %s (ID: %s)", info("Build"), success("OK"), color(Color.cyan, buildId));
}

string buildPackage(
    RecipeDir rdir,
    const(BuildConfig) config,
    DepGraphBuildInfo dgbi,
    const(DgNode) dnode,
    string stageDest = null)
{
    const srcDir = enforceSourceReady(rdir);

    auto dbi = dgbi.nodeDirectDepBuildInfos(dnode);
    const buildId = BuildId(rdir.recipe, config, dbi, stageDest);
    const bPaths = rdir.buildPaths(buildId);

    const cwd = getcwd();

    const root = absolutePath(rdir.root, cwd);
    const src = rdir.path(srcDir);
    const bdirs = BuildDirs(root, src, bPaths.build, stageDest ? stageDest : bPaths.install);

    mkdirRecurse(bPaths.build);

    rdir.recipe.build(bdirs, config, dgbi.nodeDeepDepBuildInfos(dnode));

    BuildState state = bPaths.stateFile.read();
    state.buildTime = Clock.currTime;
    bPaths.stateFile.write(state);

    return bPaths.install;
}

int buildMain(string[] args)
{
    string profileName;
    bool force;
    bool noNetwork;
    string[] optionOverrides;

    // dfmt off
    auto helpInfo = getopt(args,
        "profile|p",    &profileName,
        "no-network|N", &noNetwork,
        "force|f",      &force,
        "option|o", "Override option", &optionOverrides,
    );
    // dfmt on

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop build command", helpInfo.options);
        return 0;
    }

    auto rdir = enforceRecipe();
    auto lock = acquireRecipeLockFile(rdir);

    auto recipe = rdir.recipe;

    enforce(!recipe.isLight, new ErrorLogException(
            "Light recipes can't be built by dopamine"
    ));

    const srcDir = enforceSourceReady(rdir).absolutePath();

    const profile = enforceProfileReady(rdir, profileName);

    if (rdir.recipe.isDop)
        logInfo("%s: %s", info("Revision"), info(rdir.calcRecipeRevision()));

    auto options = rdir.readOptionFile();
    foreach(oo; optionOverrides)
    {
        parseOptionSpec(options, oo);
    }

    DepGraphBuildInfo depInfos;
    Rebindable!(const(DgNode)) rootNode;
    if (recipe.hasDependencies)
    {
        auto dag = enforceResolved(rdir);
        auto services = DepServices(
            buildDepService(Yes.system, homeCacheDir(), registryUrl()),
            buildDubDepService(),
        );
        depInfos = buildDependencies(dag, recipe, profile, services, options.forDependencies());
        rootNode = dag.root;
    }

    const config = BuildConfig(profile.subset(recipe.tools), options.forRoot());
    const buildId = BuildId(recipe, config, depInfos.nodeDirectDepBuildInfos(rootNode));

    // undocumented env var used to dump the build-id hash in a file.
    // Used by end-to-end tests to locate the build directory
    if (environment.get("DOP_E2ETEST_BUILDID"))
        write(environment["DOP_E2ETEST_BUILDID"], buildId.toString());

    const bPaths = rdir.buildPaths(buildId);
    auto bLock = acquireBuildLockFile(bPaths);

    auto state = bPaths.stateFile.read();

    if (!recipe.inTreeSrc && state.buildTime > rdir.recipeLastModified && !force)
    {
        logInfo(
            "%s: Already up-to-date (run with %s to overcome)",
            info("Build"), info("--force")
        );
        return 0;
    }

    destroy(lock);

    const dir = buildPackage(rdir, config, depInfos, rootNode);

    logInfo("%s: %s - %s", info("Build"), success("OK"), dir);

    return 0;
}
