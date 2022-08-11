module dopamine.api.v1;

import dopamine.api.attrs;

import std.datetime.systime;

struct PackageResource
{
    string name;
    string description;
    string[] versions;
}

/// only what is needed for searching and dependency resolution/fetching
struct PackageRecipeResource
{
    string name;
    @Name("version") string ver;
    string revision;
    int recipeId;
    string archiveName;
    string description;
}

@Request(Method.GET, "/v1/packages/:name")
@Response!PackageResource
struct GetPackage
{
    string name;
}

@Request(Method.GET, "/v1/packages/:name/:version/latest")
@Response!PackageRecipeResource
struct GetPackageLatestRecipe
{
    string name;
    @("version")
    string ver;
}

@Request(Method.GET, "/v1/packages/:name/:version/:revision")
@Response!PackageRecipeResource
struct GetPackageRecipe
{
    string name;
    @("version")
    string ver;
    string revision;
}

/// Recipe resource
struct RecipeResource
{
    int id;
    string packName;

    int createdBy;
    SysTime created;

    @Name("version") string ver;
    string revision;

    string archiveName;

    string description;
    string upstreamUrl;
    string license;

    string recipe;
    string readmeMimeType;
    string readme;
}

@Request(Method.GET, "/v1/recipes/:id")
@Response!RecipeResource
struct GetRecipe
{
    int id;
}

struct NewRecipeResp
{
    @Name("new") string new_; // "package", "version" or ""
    @Name("package") PackageResource pkg;
    RecipeResource recipe;
    string uploadBearerToken;
}

@Request(Method.POST, "/v1/recipes")
@Response!NewRecipeResp
@RequiresAuth
struct PostRecipe
{
    string name;
    @Name("version")
    string ver;
    string revision;
    string description;
    string upstreamUrl;
    string license;
}

static assert (isRequestFor!(PostRecipe, Method.POST));
static assert (!isRequestFor!(PostRecipe, Method.GET));
static assert (isRequestFor!(GetRecipe, Method.GET));
static assert (!isRequestFor!(GetRecipe, Method.POST));
