module dopamine.client.publish;

import dopamine.client.profile;
import dopamine.client.utils;

import dopamine.api.v1;
import dopamine.build_id;
import dopamine.cache;
import dopamine.dep.build;
import dopamine.dep.dag;
import dopamine.dep.service;
import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.registry;
import dopamine.semver;
import dopamine.util;

import squiz_box;

import std.algorithm;
import std.base64;
import std.conv;
import std.digest.sha;
import std.exception;
import std.file;
import std.format;
import std.getopt;
import std.path;
import std.range;
import std.string;
import std.typecons;

void enforceRecipeIdentity(Recipe recipe)
{
    enforce(
        // FIXME: package name rules
        recipe.name.length,
        new ErrorLogException("Invalid recipe name"),
    );

    enforce(
        // should not happen
        recipe.ver != Semver.init,
        new ErrorLogException("Invalid recipe version"),
    );

    enforce(
        recipe.revision,
        new ErrorLogException("Recipe needs a revision"),
    );
}

void enforceRecipeIntegrity(RecipeDir rdir, Profile profile, string cacheDir)
{
    auto lock = acquireRecipeLockFile(rdir);
    auto recipe = parseRecipe(rdir);

    DepInfo[string] depInfos;
    if (recipe.hasDependencies)
    {
        auto cache = new PackageCache(cacheDir);
        auto registry = new Registry();
        auto service = new DependencyService(cache, registry, No.system);
        Heuristics heuristics;
        heuristics.mode = Heuristics.Mode.pickHighest;
        heuristics.system = Heuristics.System.disallow;

        auto dag = DepDAG.prepare(recipe, profile, service, heuristics);
        dag.resolve();
        auto json = dag.toJson();
        write(rdir.depsLockFile, json.toPrettyString());

        depInfos = buildDependencies(dag, recipe, profile, service);
    }

    const cwd = getcwd();
    scope (exit)
        chdir(cwd);

    chdir(rdir.dir);

    if (!recipe.inTreeSrc)
        logInfo("%s-%s: Fetching source code", info(recipe.name), info(recipe.ver));
    const srcDir = recipe.inTreeSrc ? rdir.dir : recipe.source();

    auto config = BuildConfig(profile.subset(recipe.langs));
    const cdirs = rdir.configDirs(config);

    const root = absolutePath(rdir.dir, cwd);
    const src = absolutePath(srcDir, rdir.dir);
    const bdirs = BuildDirs(root, src, cdirs.installDir);

    mkdirRecurse(cdirs.buildDir);

    chdir(cdirs.buildDir);

    logInfo("%s-%s: Building", info(recipe.name), info(recipe.ver));
    recipe.build(bdirs, config, depInfos);
}

string[] guessRecipeFiles(RecipeDir rdir)
{
    string[] res;
    const rd = buildNormalizedPath(absolutePath(rdir.dir));
    foreach (e; dirEntries(rd, SpanMode.shallow))
    {
        const bn = baseName(e.name);

        if (bn.startsWith("."))
            continue;
        if (bn == "dop.lock")
            continue;

        if (e.isDir)
        {
            foreach (e2; dirEntries(e.name, SpanMode.breadth))
            {
                if (!e2.isDir)
                    res ~= e2.name;
            }
        }
        else
        {
            res ~= e.name;
        }
    }
    return res;
}

int publishMain(string[] args)
{
    string profileName;
    bool skipCvsClean;

    // dfmt off
    auto helpInfo = getopt(args,
        "check-profile|p", "Use specified profile to check package.", &profileName,
        "skip-cvs-clean", "Skip to check that CVS is clean", &skipCvsClean,
    );
    // dfmt on

    if (helpInfo.helpWanted)
    {
        // FIXME: document positional argument
        defaultGetoptPrinter("dop publish command", helpInfo.options);
        return 0;
    }

    const rdir = RecipeDir.enforced(".");
    auto lock = acquireRecipeLockFile(rdir);
    auto recipe = parseRecipe(rdir);
    auto profile = enforceProfileReady(rdir, recipe, profileName);

    const absRdir = buildNormalizedPath(absolutePath(rdir.dir));

    const cvs = getCvs(absRdir);
    if (!skipCvsClean)
    {
        enforce(
            cvs != Cvs.none,
            new ErrorLogException(
                "Publish requires the recipe to be under version control.\n" ~
                "Run with %s to skip this check.", info("--skip-repo-clean")
        ),
        );
        enforce(
            isRepoClean(cvs, absRdir),
            new ErrorLogException(
                "%s repo isn't clean. By default, %s is only possible with clean repo.\n" ~
                "Run with %s to skip this check.", info(cvs), info("publish"), info("--skip-repo-clean")
        ),
        );
    }

    enforceRecipeIdentity(recipe);

    const cacheDir = tempPath(null, "dop-cache", null);
    const archiveExt = ".tar.xz";
    const archivePath = tempPath(null, format!"%s-%s-%s"(recipe.name, recipe.ver, recipe.revision), archiveExt);
    const extractPath = archivePath[0 .. $ - archiveExt.length];

    mkdirRecurse(extractPath);
    mkdirRecurse(cacheDir);
    scope (exit)
    {
        mkdirRecurse(extractPath);
        mkdirRecurse(cacheDir);
    }

    auto dig = makeDigest!SHA256();

    auto files = isCvsRoot(cvs, absRdir) ? listRepoFiles(cvs, absRdir) : guessRecipeFiles(rdir);
    files
        .map!(f => fileEntry(f, absRdir))
        .boxTarXz()
        .tee(&dig)
        .writeBinaryFile(archivePath);

    scope (exit)
        remove(archivePath);

    readBinaryFile(archivePath)
        .unboxTarXz()
        .each!(e => e.extractTo(extractPath));

    logInfo("Checking recipe integrity in %s", info(extractPath));

    try
    {
        enforceRecipeIntegrity(RecipeDir.enforced(extractPath), profile, cacheDir);
        rmdirRecurse(extractPath);
    }
    catch (ServerDownException ex)
    {
        logErrorH(
            "Server %s appears down (%s), or you might be offline. " ~
                "Can't check recipe integrity and publish",
                info(ex.host), ex.reason,
        );
        return 1;
    }

    logInfo("Publish: Recipe integrity %s", success("OK"));

    auto registry = new Registry();
    try
    {
        registry.ensureAuth();
    }
    catch (Exception ex)
    {
        throw new ErrorLogException(
            "Publishing requires to be logged-in. Get a login key on the registry front-end.");
    }
    PostRecipe req;
    req.name = recipe.name;
    req.ver = recipe.ver.toString();
    req.revision = recipe.revision;
    req.archiveSha256 = Base64.encode(dig.finish()[]);
    req.archive = Base64.encode(cast(const(ubyte)[]) read(archivePath));
    auto resp = registry.sendRequest(req);
    if (!resp)
    {
        logErrorH("Creation of new recipe failed: %s", resp.error);
        return 1;
    }
    else
    {
        const pkg = resp.payload.pkg;
        const rec = resp.payload.recipe;

        if (resp.payload.newPkg)
            logInfo("Publish: New package - %s", info(pkg.name));

        logInfo("Publish: %s - %s/%s/%s", success("OK"), info(pkg.name), info(rec.ver), rec
                .revision);
    }
    return 0;
}
