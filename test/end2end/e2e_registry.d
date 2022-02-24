module e2e_registry;

import dopamine.semver;
import dopamine.cache;
import dopamine.registry.defs;

import vibe.core.core;
import vibe.data.json;
import vibe.http.common;
import vibe.http.router;
import vibe.http.server;

import std.conv;
import std.exception;
import std.file;
import std.format;
import std.path;
import std.stdio;

void packages(HTTPServerRequest req, HTTPServerResponse res)
{
    if (auto n = "name" in req.query)
    {
        auto name = *n;
        auto path = buildPath(".", name);
        if (exists(path) && isDir(path))
        {
            res.writeJsonBody(Json([
                "id": Json(name),
                "name": Json(name),
                "maintainerId": Json("e2e"),
            ]));
        }
        else {
            res.statusCode = 404;
        }
    }

    Json[] packs;
    foreach (pe; dirEntries(".", SpanMode.shallow))
    {
        if (pe.isDir)
        {
            const p = baseName(pe.name);
            packs ~= [
                Json([
                    "id": Json(p),
                    "name": Json(p),
                    "maintainerId": Json("e2e"),
                ])
            ];
        }
    }
    res.writeJsonBody(packs);
}

void packageVersions(HTTPServerRequest req, HTTPServerResponse res)
{
    Json[] versions;
    const packId = req.params["pack"];
    foreach(pe; dirEntries(".", SpanMode.shallow))
    {
        if (pe.isDir && baseName(pe.name) == packId)
        {
            foreach(ve; dirEntries(pe.name, SpanMode.shallow))
            {
                if (ve.isDir) {
                    const ver = baseName(ve.name);
                    assert(Semver.isValid(ver));
                    versions ~= Json(ver);
                }
            }
        }
    }
    res.writeJsonBody(Json(versions));
}

void packageRecipe(HTTPServerRequest req, HTTPServerResponse res)
{
    auto cache = new PackageCache(".");

    const packId = req.params["pack"];
    const ver = req.params["version"];

    const verDir = cache.packageDir(packId).versionDir(ver);
    enforce(verDir, new HTTPStatusException(404, format("No such package: %s@%s", packId, ver)));

    const rev = req.query.get("revision");
    if (rev)
    {
        const revDir = verDir.revisionDir(rev);
        serveRecipe(revDir, res);
    }
    else
    {
        auto revDirRange = verDir.revisionDirs();

        enforce(!revDirRange.empty, new HTTPStatusException(404, format("No such package: %s@%s", packId, ver)));
        serveRecipe(revDirRange.front, res);
    }
}

void serveRecipe(CacheRevisionDir revDir, HTTPServerResponse res)
{

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
    router.get("/packages", &packages);
    router.get("/packages/:pack/versions", &packageVersions);
    router.get("/packages/:pack/recipes/:version", &packageRecipe);
    router.post("/stop", &stop);

    auto listener = listenHTTP(settings, router);
    scope(exit)
        listener.stopListening();

    runEventLoop();
}
