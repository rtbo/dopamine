module dopamine.login;

import dopamine.paths;

import std.json;
import std.exception;
import std.file;
import std.string;

@safe:

struct LoginKey
{
    string name;
    string key;
}

@property bool isLoggedIn()
{
    return exists(userLoginFile());
}

LoginKey readLoginKey() @trusted
in(isLoggedIn)
{
    const json = parseJSON(cast(char[])read(userLoginFile()));
    return LoginKey(json["name"].str, json["key"].str);
}

void writeLoginKey(LoginKey lk)
{
    JSONValue jv = ["name" : lk.name, "key" : lk.key];
    const str = jv.toPrettyString();
    write(userLoginFile(), cast(const(void)[]) str);
}

LoginKey decodeLoginKey(string key)
{
    import std.base64 : Base64URLNoPadding;

    const parts = key.split('.');
    enforce(parts.length == 3, "Ill-formed login key: should be a 3 parts JWT");
    const payload = parts[1];
    const str = cast(char[]) Base64URLNoPadding.decode(payload);
    const json = parseJSON(str);
    return LoginKey(json["name"].str, key);
}

unittest
{
    const key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoidGVzdGtleSIsImlhdCI6MTYwNzU1MzY2Miwic3ViIjoi"
        ~ "NWZjZmY1YjRlNmEzYTFjZWVkMTY4NjkwIn0.0SOgGOJnZY_JvwXAXrVG-PQ8HyN82aQ5f62y0fSiRCQ";

    const lk = decodeKey(key);
    assert(lk.name == "testkey");
    assert(lk.key == key);
}
