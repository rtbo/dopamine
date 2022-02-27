module dopamine.registry.attrs;

import std.traits : hasUDA, getUDAs;

enum Method
{
    GET,
    POST,
}

struct Request
{
    Method method;
    string resource;
    int apiLevel;
}

struct Param
{
    string name;
}

/// Decorator for request query parameters.
/// Query parameters are stated in the URL after a '?'.
/// Such parameters are only allowed in GET requests.
struct Query
{
    string name;
}

enum Body;

enum RequiresAuth;

struct Response(T=ubyte[])
{
    T _ = T.init;
}

template isRequest(ReqT)
{
    enum isRequest = hasUDA!(ReqT, Request);
}

template RequestAttr(ReqT)
{
    static assert(getUDAs!(ReqT, Request).length == 1, "Only one @Request is allowed");
    enum RequestAttr = getUDAs!(ReqT, Request)[0];
}

template hasResponse(ReqT)
{
    enum hasResponse = hasUDA!(ReqT, Response);
}

template ResponseType(ReqT)
{
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
