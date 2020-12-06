module dopamine.server.cors;

import vibe.http.server;

struct CorsOptions
{
    string origin = "*";
    string[] methods = ["GET", "HEAD", "PUT", "PATCH", "POST", "DELETE"];
}

class Cors : HTTPServerRequestHandler
{
    override void handleRequest(HTTPServerRequest req, HTTPServerResponse res) @safe
    {
        if (req.method == HTTPMethod.OPTIONS) {

        }
    }
}
