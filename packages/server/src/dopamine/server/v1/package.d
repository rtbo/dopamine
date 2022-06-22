module dopamine.server.v1;

import dopamine.server.db;
import dopamine.server.v1.auth;
import dopamine.server.v1.recipes;

import vibe.http.router;

struct V1Api
{
    AuthApi auth;
    RecipesApi recipes;

    void setupRoutes(URLRouter router)
    {
        auth.setupRoutes(router);
        recipes.setupRoutes(router);
    }
}

V1Api v1Api(DbClient client)
{
    return V1Api(
        new AuthApi(client),
        new RecipesApi(client),
    );
}
