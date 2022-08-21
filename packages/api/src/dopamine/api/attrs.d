module dopamine.api.attrs;

static import vibe.data.serialization;

import std.traits : hasUDA, getUDAs;

/// HTTP method for API requests
enum Method
{
    /// GET method. Request members compose the resource URL.
    GET,
    /// POST method. Request members compose the request body, and the URL is static
    POST,
    /// PATCH method. Request 'patch' member is the JSON body and other members compose the resource URL.
    PATCH,
}

/// Decorator for a HTTP request type
struct Request
{
    Method method;
    string resource;
}

/// Decorator for a request type that requires authentication (403 is replied otherwise)
enum RequiresAuth;

/// Decorator for a request type that need authentication
/// A partial response can be supplied if no authentication is supplied
/// (e.g. user information, recipe posted by user etc.)
enum UsesAuth;

/// Decorator for request query parameter fields.
/// Query parameters are stated in the URL after a '?'.
/// Such parameters are only allowed in GET requests.
struct Query
{
    string name;
}

/// Query parameter can be omitted if they are set to their default (aka .init) value.
/// This attribute is not needed on boolean attributes and strings for which it is the default behavior.
/// (i.e. false booleans and null strings are not added on the query string)
enum OmitIfInit;

/// A Decorator to change the name of a Json field
alias Name = vibe.data.serialization.name;

/// A Decorator to make a field optional during deserialization
alias Optional = vibe.data.serialization.optional;

/// A Decorator to make a field optional during deserialization
alias EmbedNullable = vibe.data.serialization.embedNullable;

/// Decorator to specify the type of response expected by a request.
/// The response is encoded in Json.
struct Response(T)
{
    private T _ = T.init;
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
