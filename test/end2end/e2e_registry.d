module e2e_registry;

import dopamine.api.v1;
import dopamine.cache;
import dopamine.semver;

import vibe.core.core;
import vibe.data.json;
import vibe.http.common;
import vibe.http.router;
import vibe.http.server;
import vibe.http.status;

import std.conv;
import std.exception;
import std.file;
import std.format;
import std.path;
import std.stdio;

void getPackage(HTTPServerRequest req, HTTPServerResponse res)
{
    import std.algorithm : map;
    import std.array : array;

    auto cache = new PackageCache(".");

    string name = req.params["name"];
    const pkgDir = enforceHTTP(cache.packageDir(name), HTTPStatus.notFound, "No such package: " ~ name);

    string[] versions = pkgDir.versionDirs().map!(vd => vd.ver).array;

    auto payload = PackageResource(name, name, versions);

    res.writeJsonBody(serializeToJson(payload));
}

void getPackageRecipe(HTTPServerRequest req, HTTPServerResponse res)
{
    auto cache = new PackageCache(".");

    const pkgId = req.params["id"];
    const ver = req.params["version"];

    const verDir = enforceHTTP(
        cache.packageDir(pkgId).versionDir(ver),
        HTTPStatus.notFound,
        format("No such package: %s/%s", pkgId, ver),
    );

    const rev = req.query.get("revision");
    if (rev)
    {
        const revDir = verDir.revisionDir(rev);
        serveRecipe(revDir, res);
    }
    else
    {
        auto revDirRange = verDir.revisionDirs();

        enforceHTTP(
            !revDirRange.empty,
            HTTPStatus.notFound,
            format("No such package: %s/%s", pkgId, ver)
        );
        serveRecipe(revDirRange.front, res);
    }
}

void serveRecipe(CacheRevisionDir revDir, HTTPServerResponse res)
{
    import std.digest : toHexString;
    import std.digest.sha : sha1Of;

    PackageRecipeResource payload;
    payload.packageId = revDir.packageDir.name;
    payload.name = revDir.packageDir.name;
    payload.ver = revDir.versionDir.ver;
    payload.revision = revDir.revision;
    payload.recipe = cast(string)read(revDir.recipeFile);
    payload.maintainerId = "e2e";
    payload.created = "Mon. April 1st 2543";
    payload.fileList = [RecipeFile(
        "id",
        "dopamine.lua",
        getSize(revDir.recipeFile),
        toHexString(sha1Of(payload.recipe)).idup,
    )];

    res.writeJsonBody(serializeToJson(payload));
}

void stop(HTTPServerRequest req, HTTPServerResponse res)
{
    res.writeBody("", 200);
    exitEventLoop();
}

void main(string[] args)
{
    import core.time : msecs;

    ushort port = 3500;
    if (args.length >= 2)
    {
        port = args[1].to!ushort;
        args = args[0 .. 1];
    }

    auto settings = new HTTPServerSettings;
    settings.port = port;
    settings.accessLogToConsole = true;
    settings.keepAliveTimeout = 0.msecs;

    auto router = new URLRouter("/api/v1");
    router.get("/packages/:name", &getPackage); // for end-to-end, id and name have the same value
    router.get("/packages/by-name/:name", &getPackage);
    router.get("/packages/:id/recipes/:version", &getPackageRecipe);
    router.post("/stop", &stop);

    auto listener = listenHTTP(settings, router);
    scope(exit)
        listener.stopListening();

    runEventLoop();
}
