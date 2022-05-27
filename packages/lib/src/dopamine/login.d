module dopamine.login;

import dopamine.paths;
import dopamine.util;

import vibe.data.json;

import std.exception;
import std.file;
import std.string;

@safe:

struct LoginKey
{
    string userId;
    string keyName;
    string key;

    bool opCast(T : bool)() const
    {
        return userId.length && keyName.length && key.length;
    }
}

@property bool isLoggedIn()
{
    return exists(userLoginFile());
}

LoginKey readLoginKey() @trusted
in (isLoggedIn)
{
    const chars = cast(string)read(userLoginFile);
    const json = parseJsonString(chars);
    return LoginKey(json["userId"].to!string, json["keyName"].to!string, json["key"].to!string);
}

void writeLoginKey(LoginKey lk)
{
    const jv = Json(["userId": Json(lk.userId), "keyName": Json(lk.keyName), "key": Json(lk.key)]);
    write(userLoginFile(), cast(const(void)[])jv.toPrettyString());
}

LoginKey decodeLoginKey(string key) @trusted
{
    import std.base64 : Base64URLNoPadding;

    const parts = key.split('.');
    enforce(parts.length == 3, "Ill-formed login key: should be a 3 parts JWT");
    const payload = parts[1];
    const str = cast(string) Base64URLNoPadding.decode(payload);
    const json = parseJsonString(str);
    return LoginKey(json["sub"].to!string, json["name"].to!string, key);
}

unittest
{
    const key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoidGVzdGtleSIsImlhdCI6MTYwNzU1MzY2Miwic3ViIjoi"
        ~ "NWZjZmY1YjRlNmEzYTFjZWVkMTY4NjkwIn0.0SOgGOJnZY_JvwXAXrVG-PQ8HyN82aQ5f62y0fSiRCQ";

    const lk = decodeLoginKey(key);
    assert(lk.userId == "5fcff5b4e6a3a1ceed168690");
    assert(lk.keyName == "testkey");
    assert(lk.key == key);
}
