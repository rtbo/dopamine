module dopamine.api.defs;

import dopamine.semver;

import std.json;

/// A Package root object as retrieved with GET /packages
struct Package
{
    string id;
    string name;
    string[] versions;
}

package Package packageFromJson(const(JSONValue) json)
{
    import std.algorithm : map;
    import std.array : array;

    Package p;
    p.id = json["id"].str;
    p.name = json["name"].str;
    p.versions = json["versions"].arrayNoRef.map!(v => v.str).array;
    return p;
}
