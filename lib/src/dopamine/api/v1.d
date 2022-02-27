module dopamine.api.v1;

import dopamine.api.attrs;

@Request(Method.GET, "/packages", 1)
@Response!PackagePayload
struct GetPackage
{
    @Query
    string name;
}

struct PackagePayload
{
    string id;
    string name;
    string maintainerId;
}

@Request(Method.GET, "/packages/:id/versions", 1)
@Response!(string[])
struct GetPackageVersions
{
    @Param("id")
    string packageId;

    @Query
    bool latest;
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

@Request(Method.GET, "/packages/:id/recipes/:version", 1)
@Response!PackageRecipePayload
struct GetPackageRecipe {
    @Param("id")
    string packageId;

    @Param("version")
    string ver;

    @Query
    string revision;
}
