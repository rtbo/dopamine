module dopamine.api.v1;

import dopamine.api.attrs;

struct PackagePayload
{
    string id;
    string name;
    string[] versions;
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
    @Name("version") string ver;
    string revision;
    string recipe;
    string maintainerId;
    string created;
    RecipeFile[] fileList;
}

@Request(Method.GET, "/packages/:id", 1)
@Response!PackagePayload
struct GetPackage
{
    string id;
}

@Request(Method.GET, "/packages/by-name/:name", 1)
@Response!PackagePayload
struct GetPackageByName
{
    string name;
}

@Request(Method.GET, "/packages/:id/recipes/:version", 1)
@Response!PackageRecipePayload
struct GetPackageRecipe
{
    string id;

    @("version")
    string ver;

    @Query
    string revision;
}
