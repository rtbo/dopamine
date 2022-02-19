module e2e_registry;

import vibe.core.core;
import vibe.http.router;
import vibe.http.server;

import std.conv;
import std.stdio;

void packages(HTTPServerRequest req, HTTPServerResponse res)
{}

void packageVersions(HTTPServerRequest req, HTTPServerResponse res)
{}

void main(string[] args)
{
    ushort port = 3500;
    if (args.length >= 2)
    {
        port = args[1].to!ushort;
    }

    auto settings = new HTTPServerSettings;
    settings.hostName = "localhost";
    settings.port = port;
    settings.accessLogToConsole = true;

    auto router = new URLRouter("/api/v1");
    router.get("/packages", &packages);
    router.get("/packages/:pack/versions", &packageVersions);

    listenHTTP(settings, router);

    runApplication();
}
