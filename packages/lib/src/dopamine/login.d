module dopamine.login;

import dopamine.paths;
import dopamine.util;

import vibe.data.json;

import std.algorithm;
import std.exception;
import std.file;
import std.string;

@safe:

private string getHost(string url)
{
    if (url.startsWith("http://"))
        url = url["http://".length .. $];
    if (url.startsWith("https://"))
        url = url["https://".length .. $];

    url = url[0 .. $ - find(url, "/").length];

    return url;
}

bool hasLoginToken(string registry)
{
    const fn = userLoginFile();
    if (!exists(fn))
        return false;

    const chars = (() @trusted => assumeUnique(cast(const(char)[]) read(fn)))();
    const json = parseJsonString(chars);
    return json[getHost(registry)].type == Json.Type.string;
}

string readLoginToken(string registry)
in (hasLoginToken(registry))
{
    const chars = (() @trusted => assumeUnique(cast(const(char)[]) read(userLoginFile)))();
    const json = parseJsonString(chars);
    return json[getHost(registry)].get!string;
}

void writeLoginToken(string registry, string token)
{
    Json json;

    const fn = userLoginFile();
    if (exists(fn))
    {
        const chars = (() @trusted => assumeUnique(cast(const(char)[]) read(fn)))();
        json = parseJsonString(chars);
    }
    else
    {
        json = Json.emptyObject;
    }

    json[getHost(registry)] = Json(token);
    write(fn, cast(const(void)[]) json.toPrettyString());
}
