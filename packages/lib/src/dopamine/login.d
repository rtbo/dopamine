module dopamine.login;

import dopamine.paths;
import dopamine.util;

import vibe.data.json;

import std.exception;
import std.file;
import std.string;

@safe:

bool isLoggedIn(string registry)
{
    const fn = userLoginFile();
    if (!exists(fn))
        return false;

    const chars = (() @trusted => assumeUnique(cast(const(char)[]) read(fn)))();
    const json = parseJsonString(chars);
    return json[registry].type == Json.Type.string;
}

string readLoginToken(string registry)
in (isLoggedIn(registry))
{
    const chars = (() @trusted => assumeUnique(cast(const(char)[]) read(userLoginFile)))();
    const json = parseJsonString(chars);
    return json[registry].get!string;
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

    json[registry] = Json(token);
    write(fn, cast(const(void)[]) json.toPrettyString());
}
