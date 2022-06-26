module dopamine.server.v1;

import dopamine.server.db;
import dopamine.server.v1.recipes;

import vibe.http.router;

struct V1Api
{
    RecipesApi recipes;

    void setupRoutes(URLRouter router)
    {
        recipes.setupRoutes(router);
    }
}

V1Api v1Api(DbClient client)
{
    return V1Api(
        new RecipesApi(client),
    );
}
