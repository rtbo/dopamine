module dopamine.api.v1;

import dopamine.api.attrs;

import std.datetime.systime;

/+ packages API +/

struct PackageResource
{
    string name;
    string description;
    string[] versions;
}

/// only what is needed for dependency resolution/fetching
struct PackageRecipeResource
{
    string name;
    @Name("version") string ver;
    string revision;
    int recipeId;
    string archiveName;
    string description;
}

struct PackageSearchEntry
{
    string name;
    string description;
    // numVersions and numRecipes are useful with `latestOnly` search option
    uint numVersions;
    uint numRecipes;
    PkgVersionSearchEntry[] versions;
}

struct PkgVersionSearchEntry
{
    @Name("version")
    string ver;
    PkgRecipeSearchEntry[] recipes;
}

struct PkgRecipeSearchEntry
{
    string revision;
    @Optional
    string createdBy;
    SysTime created;
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

/// Search packages and package recipes according a pattern and options
@Request(Method.GET, "/v1/packages")
@Response!(PackageSearchEntry[])
struct SearchPackages
{
    /// Pattern to search for.
    /// By default, the pattern is searched in the name and description or each recipe.
    @Query("q")
    string pattern;

    /// If defined, pattern is interpreted as a POSIX regular expression.
    /// Otherwise it is a simple substring matching
    @Query
    bool regex;

    /// If defined, the string matching is case sensitive.
    /// Otherwise it is case insensitive
    @Query("cs")
    bool caseSensitive;

    /// If defined, pattern is only tested against package name.
    /// Incompatible with extended
    @Query
    bool nameOnly;

    /// If defined, pattern is also tested against extended content, like ReadMe and Recipe.
    /// Can take substancially longer time as the extended content is not always indexed.
    /// Incompatible with nameOnly
    @Query
    bool extended;

    /// if defined, a single version and revision is returned per package
    /// (the latest revision of the highest version)
    @Query
    bool latestOnly;

    /// limit the number of distinct packages returned
    @Query @OmitIfInit
    int limit;

    /// limit the total number of recipe entries returned.
    @Query @OmitIfInit
    int recLimit;
}

/+ recipes API +/

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
    /// mime type of readme
    string readmeMt;
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
@Response!NewRecipeResp @RequiresAuth
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

static assert(isRequestFor!(PostRecipe, Method.POST));
static assert(!isRequestFor!(PostRecipe, Method.GET));
static assert(isRequestFor!(GetRecipe, Method.GET));
static assert(!isRequestFor!(GetRecipe, Method.POST));
