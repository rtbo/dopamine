module dopamine.api.attrs;

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
    int apiLevel;
}

/// Decorator for a request parameter field
struct Param
{
    string name;
}

/// Decorator for request query parameter fields.
/// Query parameters are stated in the URL after a '?'.
/// Such parameters are only allowed in GET requests.
struct Query
{
    string name;
}

/// Decorator for a request Json body
enum JsonBody;

/// Decorator for a request type that requires authentification
enum RequiresAuth;

/// Decorator to specify the type of response expected by a request
struct Response(T=ubyte[])
{
    private T _ = T.init;
}

/// Checks whether `ReqT` is a request type
template isRequest(ReqT)
{
    enum isRequest = hasUDA!(ReqT, Request);
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
