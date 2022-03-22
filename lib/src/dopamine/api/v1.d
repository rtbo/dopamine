module dopamine.api.v1;

import dopamine.api.attrs;

struct PackageResource
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

struct PackageRecipeResource
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

enum level = 1;

@Request(Method.GET, "/packages/:id", level)
@Response!PackageResource
struct GetPackage
{
    string id;
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
    string id;

    @("version")
    string ver;

    @Query
    string revision;
}
