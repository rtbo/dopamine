module dopamine.api.v1;

import dopamine.api.attrs;

import std.datetime.systime;

struct PackageResource
{
    int id;
    string name;
    string[] versions;
}

struct RecipeFile
{
    int id;
    string name;
    size_t size;
}

struct PackageRecipeResource
{
    int packageId;
    string name;
    @Name("version") string ver;
    string revision;
    string recipe;
    int maintainerId;
    SysTime created;
    RecipeFile[] fileList;
}

enum level = 1;

@Request(Method.GET, "/packages/:id", level)
@Response!PackageResource
struct GetPackage
{
    int id;
}

@Request(Method.GET, "/packages/by-name/:name", level)
@Response!PackageResource
struct GetPackageByName
{
    string name;
}

@Request(Method.GET, "/packages/:id/recipes/:version", level)
@Response!PackageRecipeResource
struct GetPackageRecipe
{
    @("id")
    int packageId;

    @("version")
    string ver;

    @Query
    string revision;
}
