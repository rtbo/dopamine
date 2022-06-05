module dopamine.api.v1;

import dopamine.api.attrs;

import std.datetime.systime;

enum level = 1;

struct PackageResource
{
    string name;
    int maintainerId;
    SysTime created;
    string[] versions;
}

@Request(Method.GET, "/packages/:name", level)
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
    string recipe;
    int maintainerId;
    SysTime created;
}

@Request(Method.GET, "/packages/:name/:version/latest", level)
@Response!RecipeResource
struct GetLatestRecipeRevision
{
    string name;
    @("version")
    string ver;
}

@Request(Method.GET, "/packages/:name/:version/:revision", level)
@Response!RecipeResource
struct GetRecipeRevision
{
    string name;
    @("version")
    string ver;
    string revision;
}


@Request(Method.GET, "/recipes/:id", level)
@Response!RecipeResource
struct GetRecipe
{
    int id;
}

@Request(Method.GET, "/recipes/:id/files", level)
@Response!(const(RecipeFile)[])
struct GetRecipeFiles
{
    int id;
}

@Request(Method.GET, "/recipes/:id/archive", level)
@Response!(DownloadInfo)
struct GetRecipeArchive
{
    int id;
}

struct RecipeFile
{
    string name;
    ulong size;
}

struct DownloadInfo
{
    string filename;
    ulong size;
    string sha1;
    string url;
}