module dopamine.server.cors;

import vibe.http.common;
import vibe.http.router;
import vibe.http.server;

import std.algorithm;
import std.string;

// porting (more or less) npm cors package

@safe:

HTTPServerRequestDelegateS cors(CorsOptions opts = CorsOptions.init)
{
    return (scope req, scope resp) { corsImpl(opts, req, resp); };
}

struct CorsOptions
{
    /// Safe-listed origins (which can be ["*"])
    /// By default, will use `Origin` header
    string[] origin;

    /// Configures `Access-Control-Allow-Methods`
    /// By default, will use [GET,HEAD,PUT,PATCH,POST,DELETE]
    HTTPMethod[] methods;

    /// Configures `Access-Control-Allow-Headers`
    /// If empty, will use `Access-Control-Request-Headers`
    string[] allowedHeaders;

    /// Configures `Access-Control-Exposed-Headers`
    /// By default the header is omitted
    string[] exposedHeaders;

    /// Configures `Access-Control-Allow-Credentials`
    /// By default the header is omitted
    bool credientials;

    /// Configures `Access-Control-Max-Age`
    /// By default the header is omitted
    uint maxAge;

    /// If set, the preflight will continue.
    /// This may result in 404 if no further route handles it.
    bool preflightContinue;

    /// Success status of preflight OPTIONS request
    /// 204 is used by default
    int preflightSuccessStatus;
}

private void varyOrigin(scope HTTPServerResponse resp, string orig)
{
    pragma(inline, true)

    resp.headers["Access-Control-Allow-Origin"] = orig;
    resp.headers["Vary"] = "Origin";
}

private void corsImpl(scope ref CorsOptions opts, scope HTTPServerRequest req, scope HTTPServerResponse resp)
{
    import std.conv;

    if (opts.origin.length == 0)
    {
        if (auto origin = "Origin" in req.headers)
            varyOrigin(resp, *origin);
    }
    else if (opts.origin.length == 1 && opts.origin[0] == "*")
    {
        resp.headers["Access-Control-Allow-Origin"] = "*";
    }
    else if (auto origin = "Origin" in req.headers)
    {
        // general case, we use the origin request header if it is safe-listed
        if (opts.origin.canFind(*origin))
            varyOrigin(resp, *origin);
    }

    if (opts.credientials)
        resp.headers["Access-Control-Allow-Credentials"] = "true";

    if (opts.exposedHeaders)
        resp.headers["Access-Control-Exposed-Headers"] = opts.exposedHeaders.join(", ");

    if (req.method != HTTPMethod.OPTIONS)
        return;

    if (opts.methods)
        resp.headers["Access-Control-Allow-Methods"] = opts.methods.map!(
            m => httpMethodString(m)).join(", ");
    else
        resp.headers["Access-Control-Allow-Methods"] = "GET, HEAD, PUT, PATCH, POST, DELETE";

    if (opts.allowedHeaders)
        req.headers["Access-Control-Allow-Headers"] = opts.allowedHeaders.join(", ");
    else if (auto reqHead = "Access-Control-Request-Headers" in req.headers)
    {
        resp.headers["Access-Control-Allow-Headers"] = *reqHead;
        resp.headers["Vary"] = "Access-Control-Allow-Headers";
    }

    if (opts.maxAge)
        req.headers["Access-Control-Max-Age"] = opts.maxAge.to!string;

    if (!opts.preflightContinue)
    {
        resp.statusCode = opts.preflightSuccessStatus ? opts.preflightSuccessStatus : 204;
        resp.writeBody("");
    }
}
