module dopamine.registry.defs;

import dopamine.semver;

import vibe.data.json;

/// A Package root object as retrieved with GET /packages
struct PackagePayload
{
    string id;
    string name;
    string maintainerId;
}

package PackagePayload packageFromJson(const(Json) json)
{
    import std.algorithm : map;
    import std.array : array;

    PackagePayload p;
    p.id = json["id"].to!string;
    p.name = json["name"].to!string;
    p.maintainerId = json["maintainerId"].to!string;
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

package PackageRecipePayload packageRecipeFromJson(const(Json) json)
{
    import std.algorithm : map;
    import std.array : array;

    PackageRecipePayload pr;
    pr.packageId = json["packageId"].to!string;
    pr.name = json["name"].to!string;
    pr.ver = json["version"].to!string;
    pr.rev = json["revision"].to!string;
    pr.recipe = json["recipe"].to!string;
    pr.maintainerId = json["maintainerId"].to!string;
    pr.created = json["created"].to!string;
    pr.fileList = json["fileList"][].map!(
        jv => deserializeJson!RecipeFile(jv)
    ).array;

    return pr;
}
