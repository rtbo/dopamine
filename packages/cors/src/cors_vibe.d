module cors_vibe;

import vibe.http.common;
import vibe.http.server;

import std.algorithm;

// porting (more or less) npm cors package

@safe:

HTTPServerRequestHandler cors(CorsOptions opts = CorsOptions.init)
{
    return new Cors(opts);
}

struct CorsOptions
{
    /// Configures `Access-Control-Allow-Origins`
    /// Safe-listed origins (which can be ["*"])
    /// By default, will use `Origin` header
    string[] allowedOrigins;

    /// Configures `Access-Control-Allow-Methods`
    /// By default, will use [GET,HEAD,PUT,PATCH,POST,DELETE]
    HTTPMethod[] allowedMethods;

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
    /// By default, all preflight requests will receive success code with configured
    /// CORS headers.
    bool preflightContinue;

    /// Success status of preflight OPTIONS request
    /// 204 is used by default
    int preflightSuccessStatus;
}

private void varyOrigin(HTTPServerResponse resp, string orig)
{
    pragma(inline, true)

    resp.headers["Access-Control-Allow-Origin"] = orig;
    resp.headers["Vary"] = "Origin";
}

private class Cors : HTTPServerRequestHandler
{
    CorsOptions opts;
    string allowedMethods;
    string allowedHeaders;
    string exposedHeaders;
    string maxAge;

    this(CorsOptions opts)
    {
        import std.conv;
        import std.string;

        // pre-computing what can be pre-computed
        if (opts.allowedMethods)
            allowedMethods = opts.allowedMethods.map!(m => httpMethodString(m)).join(",");
        else
            allowedMethods = "GET,HEAD,PUT,PATCH,POST,DELETE";

        if (opts.allowedHeaders)
            allowedHeaders = opts.allowedHeaders.join(",");

        if (opts.exposedHeaders)
            exposedHeaders = opts.exposedHeaders.join(",");

        if (opts.maxAge)
            maxAge = opts.maxAge.to!string;

        if (opts.preflightSuccessStatus == 0)
            opts.preflightSuccessStatus = 204;

        this.opts = opts;
    }

    void handleRequest(HTTPServerRequest req, HTTPServerResponse resp)
    {
        if (opts.allowedOrigins.length == 0)
        {
            if (auto origin = "Origin" in req.headers)
                varyOrigin(resp, *origin);
        }
        else if (opts.allowedOrigins.length == 1 && opts.allowedOrigins[0] == "*")
        {
            resp.headers["Access-Control-Allow-Origin"] = "*";
        }
        else if (auto origin = "Origin" in req.headers)
        {
            // general case, we use the origin request header if it is safe-listed
            if (opts.allowedOrigins.canFind(*origin))
                varyOrigin(resp, *origin);
        }

        if (opts.credientials)
            resp.headers["Access-Control-Allow-Credentials"] = "true";

        if (exposedHeaders)
            resp.headers["Access-Control-Exposed-Headers"] = exposedHeaders;

        if (req.method != HTTPMethod.OPTIONS)
            return;

        resp.headers["Access-Control-Allow-Methods"] = allowedMethods;

        if (allowedHeaders)
        {
            req.headers["Access-Control-Allow-Headers"] = allowedHeaders;
        }
        else if (auto reqHead = "Access-Control-Request-Headers" in req.headers)
        {
            resp.headers["Access-Control-Allow-Headers"] = *reqHead;
            resp.headers["Vary"] = "Access-Control-Allow-Headers";
        }

        if (maxAge)
            req.headers["Access-Control-Max-Age"] = maxAge;

        if (!opts.preflightContinue)
        {
            resp.statusCode = opts.preflightSuccessStatus;
            resp.writeBody("");
        }
    }
}
