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
        recipe.name.length && recipe.description.length && recipe.license.length && recipe.upstreamUrl.length,
        new ErrorLogException(
            "The following fields are needed to publish a recipe:\n - %s\n - %s\n - %s\n - %s",
            info("name"), info("description"), info("license"), info("upstream_url")
    )
    );

    const forbidden = ["/", "\\", "@"];
    foreach (c; forbidden)
    {
        enforce(
            !recipe.name.canFind(c),
            new ErrorLogException(
                "Invalid recipe name. Illegal character: %s", info(c)
        )
        );
    }

    enforce(
        // should not happen
        recipe.ver != Semver.init,
        "Invalid recipe version",
    );

    enforce(
        recipe.revision.length,
        "Recipe needs a revision",
    );
}

void enforceRecipeIntegrity(RecipeDir rdir,
    Profile profile,
    string cacheDir,
    string revision,
    OptionSet options)
{
    auto lock = acquireRecipeLockFile(rdir);
    auto recipe = rdir.recipe;

    recipe.revision = revision;

    DepInfo[string] depInfos;
    if (recipe.hasDependencies)
    {
        auto services = DepServices(buildDepService(No.system, cacheDir), buildDubDepService());
        Heuristics heuristics;
        heuristics.mode = Heuristics.Mode.pickHighest;
        heuristics.system = Heuristics.System.disallow;

        auto dag = DepDAG.prepare(rdir, profile, services, heuristics);
        dag.resolve();
        auto json = dag.toJson();
        write(rdir.depsLockFile, json.toPrettyString());

        depInfos = buildDependencies(dag, recipe, profile, services);
    }

    if (!recipe.inTreeSrc)
        logInfo("%s-%s: Fetching source code", info(recipe.name), info(recipe.ver));
    const srcDir = recipe.inTreeSrc ? rdir.root : recipe.source();

    const config = BuildConfig(profile.subset(recipe.tools), options);
    const buildId = BuildId(recipe, config);
    const bPaths = rdir.buildPaths(buildId);

    const bdirs = BuildDirs(rdir.root, rdir.path(srcDir), bPaths.build, bPaths.install);

    mkdirRecurse(bPaths.build);

    logInfo("%s-%s: Building", info(recipe.name), info(recipe.ver));
    recipe.build(bdirs, config, depInfos);
}

int publishMain(string[] args)
{
    string profileName;
    bool skipCvsClean;
    string[] optionOverrides;

    // dfmt off
    auto helpInfo = getopt(args,
        "check-profile|p", "Use specified profile to check package.", &profileName,
        "skip-cvs-clean", "Skip to check that CVS is clean", &skipCvsClean,
        "option|o", "Override option for the integrity check", &optionOverrides,
    );
    // dfmt on

    if (helpInfo.helpWanted)
    {
        // FIXME: document positional argument
        defaultGetoptPrinter("dop publish command", helpInfo.options);
        return 0;
    }

    auto rdir = enforceRecipe();
    auto lock = acquireRecipeLockFile(rdir);
    auto recipe = rdir.recipe;

    enforce(!recipe.isDub, new ErrorLogException(
            "Dub packages can't be published to Dopamine registry"
    ));
    enforce(!recipe.isLight, new ErrorLogException(
            "Light recipes can't be published"
    ));

    auto profile = enforceProfileReady(rdir, profileName);

    const cvs = getCvs(rdir.root);
    if (!skipCvsClean)
    {
        enforce(
            cvs != Cvs.none,
            new ErrorLogException(
                "Publish requires the recipe to be under version control.\n" ~
                "Run with %s to skip this check.", info("--skip-cvs-clean")
        ),
        );
        enforce(
            isRepoClean(cvs, rdir.root),
            new ErrorLogException(
                "%s repo isn't clean. By default, %s is only possible with a clean repo.\n" ~
                "Run with %s to skip this check.", info(cvs), info("publish"), info(
                "--skip-cvs-clean")
        ),
        );
    }

    logInfo("%s: %s", info("Revision"), info(rdir.calcRecipeRevision()));

    enforceRecipeIdentity(recipe);

    const cacheDir = tempPath(null, "dop-cache", null);
    const archivePath = buildPath(tempDir(), format!"%s-%s-%s.tar.xz"(recipe.name, recipe.ver, recipe
            .revision));
    const extractPath = archivePath[0 .. $ - ".tar.xz".length];

    mkdirRecurse(extractPath);
    mkdirRecurse(cacheDir);
    scope (exit)
    {
        rmdirRecurse(cacheDir);
        rmdirRecurse(extractPath);
    }

    logInfo("%s: preparing recipe archive...", info("Publish"));

    auto dig = makeDigest!SHA256();

    rdir.getAllRecipeFiles()
        .tee!(f => logInfo("    Including %s", info(f)))
        .map!(f => fileEntry(f, rdir.root))
        .boxTarXz()
        .tee(&dig)
        .writeBinaryFile(archivePath);

    scope (exit)
        remove(archivePath);

    readBinaryFile(archivePath)
        .unboxTarXz()
        .each!(e => e.extractTo(extractPath));

    auto options = rdir.readOptionFile();
    foreach (oo; optionOverrides)
    {
        parseOptionSpec(options, oo);
    }

    logInfo("Checking recipe integrity in %s", info(extractPath));

    try
    {
        enforceRecipeIntegrity(enforceRecipe(extractPath), profile, cacheDir, recipe.revision, options);
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

    logInfo("%s: Recipe integrity %s", info("Publish"), success("OK"));

    auto registry = new Registry();
    try
    {
        registry.ensureAuth();
    }
    catch (Exception ex)
    {
        throw new ErrorLogException(
            "Could not log to %s (%s).\nPublishing requires to be logged-in. " ~
                "Get a login key on the registry front-end.",
                info(registry.host), ex.msg
        );
    }

    PostRecipe req;
    req.name = recipe.name;
    req.ver = recipe.ver.toString();
    req.revision = recipe.revision;
    req.description = recipe.description;
    req.license = recipe.license;
    req.upstreamUrl = recipe.upstreamUrl;
    auto resp = registry.sendRequest(req);
    if (!resp)
    {
        logErrorH("Creation of new recipe failed: %s", resp.error);
        return 1;
    }

    NewRecipeResp newRecResp = resp.payload;

    const rec = newRecResp.recipe;
    const sha256 = Base64.encode(dig.finish()[]).idup;

    switch (newRecResp.new_)
    {
    case "package":
        logInfo("Publish: New package - %s/%s", info(rec.name), info(rec.ver));
        break;
    case "version":
        logInfo("Publish: Adding version %s to package %s", info(rec.ver), info(rec.name));
        break;
    case "":
        logInfo("Publish: Adding new revision to %s/%s", info(rec.name), info(rec.ver));
        break;
    default:
        debug assert(false, "unknown new_ field value");
        else break;
    }

    logInfo("Uploading archive and checking archive...");
    registry.uploadArchive(newRecResp.uploadBearerToken, archivePath, sha256);

    logInfo("Publish: %s - %s/%s/%s", success("OK"), info(rec.name), info(rec.ver), rec
            .revision);
    return 0;
}
