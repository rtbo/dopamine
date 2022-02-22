module dopamine.server.main;

import vibe.core.core;
import vibe.http.router;
import vibe.http.server;

import std.conv;
import std.format;
import std.process;

enum currentApiLevel = 1;

void main()
{
    auto hostName = environment.get("DOP_SERVER_HOSTNAME");
    auto port = environment.get("DOP_SERVER_PORT");

    auto settings = new HTTPServerSettings;
    if (hostName)
        settings.hostName = hostName;
    if (port)
        settings.port = port.to!ushort;

    const prefix = format("/api/v%s", currentApiLevel);
    auto router = new URLRouter(prefix);

    auto listener = listenHTTP(settings, router);
    scope(exit)
        listener.stopListening();

    runApplication();
}
