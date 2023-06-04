module app;

import vibe.core.core;
import vibe.http.server;

void main()
{
	listenHTTP(":8080", &handleRequest);
	runApplication();
}

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	if (req.path == "/")
		res.writeBody("Hello, World!");
}
