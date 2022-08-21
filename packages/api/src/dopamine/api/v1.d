module dopamine.api.v1;

import dopamine.api.attrs;

import vibe.data.json;

import std.datetime.systime;
import std.typecons;

@safe:

/+ users API +/

struct UserResource
{
    /// User pseudo
    string pseudo;

    /// User private info.
    /// Only returned if allowed by the user privacy settings.
    @Optional string email;
    /// ditto
    @Optional string name;
    /// ditto
    @Optional string avatarUrl;

    /// Privacy flags only returned for the authenticated user
    @Optional PrivacyFlags privacyFlags;
}

enum PrivacyFlags
{
    none = 0,
    email = 1,
    name = 2,
    avatarUrl = 4,
}

@property bool emailPrivate(PrivacyFlags pf)
{
    return (pf & PrivacyFlags.email) == PrivacyFlags.email;
}

@property bool namePrivate(PrivacyFlags pf)
{
    return (pf & PrivacyFlags.name) == PrivacyFlags.name;
}

@property bool avatarUrlPrivate(PrivacyFlags pf)
{
    return (pf & PrivacyFlags.avatarUrl) == PrivacyFlags.avatarUrl;
}

struct UserPatch
{
    @EmbedNullable
    Nullable!string pseudo;

    @EmbedNullable
    Nullable!string name;

    @EmbedNullable
    Nullable!string avatarUrl;

    @EmbedNullable
    Nullable!PrivacyFlags privacyFlags;
}

/// Get user information.
/// If authentication is supplied, a user can retrieve its own private info.
/// Otherwise, returned private info depends on the user privacy settings
@Request(Method.GET, "/v1/users/:pseudo")
@UsesAuth
@Response!UserResource
struct GetUser
{
    string pseudo;
}

/// Change user info
@Request(Method.PATCH, "/v1/users/:pseudo")
@RequiresAuth
@Response!UserResource
struct PatchUser
{
    string pseudo;
    UserPatch patch;
}


/+ packages API +/

struct PackageResource
{
    string name;
    string description;

    PackageVersionResource[] versions;
}

struct PackageVersionResource
{
    @Name("version")
    string ver;

    PackageRecipeResource[] recipes;
}


/// only what is needed for dependency resolution/fetching
struct PackageRecipeResource
{
    int recipeId;
    string revision;
    string archiveName;
}

struct PackageSearchEntry
{
    string name;
    string description;
    string lastVersion;
    string lastRecipeRev;
    uint numVersions;
    uint numRecipes;
}

@Request(Method.GET, "/v1/packages/:name")
@Response!PackageResource
struct GetPackage
{
    string name;
}

/// Search packages and package recipes according a pattern and options.
/// The packages are returned in the order of the most downloaded first.
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

    // offset and limit allows basic server-side pagination
    // this is not perfect as the query result or package order
    // may change between one page to the next.
    // If not acceptable, client side pagination should be preferred.

    /// offset of the returned packages returned
    @Query @OmitIfInit
    int offset;

    /// limit the number of packages returned
    @Query @OmitIfInit
    int limit;
}

/+ recipes API +/

/// Recipe resource
struct RecipeResource
{
    /// Identifier of the recipe on the registry
    int id;

    /// Name of the package
    string name;

    /// Identifier of the user who published the recipe
    int createdBy;
    /// Date/time of publication of this recipe
    SysTime created;

    /// Version of this package (Semver compliant)
    @Name("version") string ver;
    /// Revision of this recipe
    string revision;

    /// Archive name of this recipe. Can be used to build a download URL
    string archiveName;

    /// Description of the package (as written in the recipe)
    string description;
    /// Upstream URL of the package (as written in the recipe)
    string upstreamUrl;
    /// License of the package (as written in the recipe)
    string license;

    /// Recipe file content (aka. dopamine.lua)
    string recipe;
    /// Mime type of ReadMe file (if any)
    string readmeMt;
    /// Content of the ReadMe file (if any)
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
