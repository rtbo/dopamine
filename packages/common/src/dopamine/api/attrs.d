module dopamine.api.attrs;

static import vibe.data.serialization;

import std.traits : hasUDA, getUDAs;

/// HTTP method for API requests
enum Method
{
    GET,
    POST,
}

/// Decorator for a HTTP request type
struct Request
{
    Method method;
    string resource;
}

/// Decorator for a request type that requires authentification
enum RequiresAuth;

/// Decorator for request query parameter fields.
/// Query parameters are stated in the URL after a '?'.
/// Such parameters are only allowed in GET requests.
struct Query
{
    string name;
}

/// Decorator for a request Json body
enum JsonBody;

/// A Decorator to change the name of a Json field
alias Name = vibe.data.serialization.name;

/// Decorator to specify the type of response expected by a request.
/// The response is encoded in Json.
struct Response(T)
{
    private T _ = T.init;
}

/// Decorator to specify that the request is an endpoint
/// to download files. Download end-points have several additional
/// features such as Content-Range, Digest, Content-Disposition, ...
struct DownloadEndpoint
{
}

/// Checks whether `ReqT` is a request type
template isRequest(ReqT)
{
    enum isRequest = hasUDA!(ReqT, Request);
}

/// Checks whether `ReqT` is a request type for the given method
template isRequestFor(ReqT, Method method)
{
    static if (hasUDA!(ReqT, Request))
    {
        enum isRequestFor = getUDAs!(ReqT, Request)[0].method == method;
    }
    else
    {
        enum isRequestFor = false;
    }
}

/// Retrieves the `Request` value attached to `ReqT`.
template RequestAttr(ReqT)
{
    static assert(isRequest!ReqT, ReqT.stringof ~ " do not appear to be a valid Request type");
    static assert(getUDAs!(ReqT, Request).length == 1, "Only one @Request is allowed");

    enum RequestAttr = getUDAs!(ReqT, Request)[0];
}

/// Checks whether the request expects a response body
template hasResponse(ReqT)
{
    static assert(isRequest!ReqT, ReqT.stringof ~ " do not appear to be a valid Request type");

    enum hasResponse = hasUDA!(ReqT, Response);
}

/// Retrives the expected response body of `ReqT`, or `void` if none is expected.
template ResponseType(ReqT)
{
    static assert(isRequest!ReqT, ReqT.stringof ~ " do not appear to be a valid Request type");

    static if (hasResponse!ReqT)
    {
        static assert(getUDAs!(ReqT, Response).length == 1, "Only one @Response is allowed");
        alias ResponseType = typeof(getUDAs!(ReqT, Response)[0]._);
    }
    else
    {
        alias ResponseType = void;
    }
}

/// Checks whether the request is a download endpoint
template isDownloadEndpoint(ReqT)
{
    static assert(isRequest!ReqT, ReqT.stringof ~ " do not appear to be a valid Request type");

    enum isDownloadEndpoint = hasUDA!(ReqT, DownloadEndpoint);
}
