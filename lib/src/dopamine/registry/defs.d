module dopamine.registry.defs;

import dopamine.semver;

import std.json;

/// A Package root object as retrieved with GET /packages
struct PackagePayload
{
    string id;
    string name;
    string maintainerId;
}

string[] jsonStringArray(const(JSONValue) jv)
{
    import std.algorithm : map;
    import std.array : array;

    return jv.arrayNoRef.map!(v => v.str).array;
}

package PackagePayload packageFromJson(const(JSONValue) json)
{
    import std.algorithm : map;
    import std.array : array;

    PackagePayload p;
    p.id = json["id"].str;
    p.name = json["name"].str;
    p.maintainerId = json["maintainerId"].str;
    return p;
}

struct PackageRecipePost
{
    /// The id of the package
    string packageId;
    /// The version of the package
    string ver;
    /// The revision of the package - must be unique whatever the version
    string rev;
    /// The lua file content
    string recipe;
}

struct PackageRecipeGet
{
    /// The id of the package
    string packageId;
    /// The version of the package
    string ver;
    /// The revision of the package - must be unique whatever the version
    string rev;
}

struct RecipeFile
{
    string id;
    string name;
    size_t size;
    string sha1;
}

struct PackageRecipePayload
{
    string packageId;
    string name;
    string ver;
    string rev;
    string recipe;
    string maintainerId;
    string created;
    RecipeFile[] fileList;
}

package PackageRecipePayload packageRecipeFromJson(const(JSONValue) json)
{
    import std.algorithm : map;
    import std.array : array;

    PackageRecipePayload pr;
    pr.packageId = json["packageId"].str;
    pr.name = json["name"].str;
    pr.ver = json["version"].str;
    pr.rev = json["revision"].str;
    pr.recipe = json["recipe"].str;
    pr.maintainerId = json["maintainerId"].str;
    pr.created = json["created"].str;
    pr.fileList = json["fileList"].array.map!(
        jv => RecipeFile(jv["id"].str, jv["name"].str, jv["size"].integer, jv["sha1"].str)
    ).array;

    return pr;
}
