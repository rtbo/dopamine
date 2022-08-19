module dopamine.registry.v1;

import dopamine.registry.archive;
import dopamine.registry.db;
import dopamine.registry.v1.packages;
import dopamine.registry.v1.recipes;

import vibe.http.router;

struct V1Api
{
    PackagesApi packages;
    RecipesApi recipes;

    void setupRoutes(URLRouter router)
    {
        packages.setupRoutes(router);
        recipes.setupRoutes(router);
    }
}

V1Api v1Api(DbClient client, ArchiveManager archiveMgr)
{
    return V1Api(
        new PackagesApi(client),
        new RecipesApi(client, archiveMgr),
    );
}
