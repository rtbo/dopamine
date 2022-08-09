module dopamine.api.v1;

import dopamine.api.attrs;

import std.datetime.systime;

struct PackageResource
{
    string name;
    int maintainerId;
    SysTime created;
    string[] versions;
}

@Request(Method.GET, "/v1/packages/:name")
@Response!PackageResource
struct GetPackage
{
    string name;
}

struct RecipeResource
{
    int id;
    @Name("version") string ver;
    string revision;
    int maintainerId;
    SysTime created;
    string archiveName;
}

@Request(Method.GET, "/v1/packages/:name/:version/latest")
@Response!RecipeResource
struct GetLatestRecipeRevision
{
    string name;
    @("version")
    string ver;
}

@Request(Method.GET, "/v1/packages/:name/:version/:revision")
@Response!RecipeResource
struct GetRecipeRevision
{
    string name;
    @("version")
    string ver;
    string revision;
}


@Request(Method.GET, "/v1/recipes/:id")
@Response!RecipeResource
struct GetRecipe
{
    int id;
}

struct NewRecipeResp
{
    @Name("new") bool newPkg;
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
}

static assert (isRequestFor!(PostRecipe, Method.POST));
static assert (!isRequestFor!(PostRecipe, Method.GET));
static assert (isRequestFor!(GetRecipe, Method.GET));
static assert (!isRequestFor!(GetRecipe, Method.POST));
