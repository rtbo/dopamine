module dopamine.registry.v1.recipes;

import dopamine.registry.archive;
import dopamine.registry.auth;
import dopamine.registry.db;
import dopamine.registry.utils;
import dopamine.registry.v1.packages;

import dopamine.api.v1;
import dopamine.semver;

import pgd.conn;

import vibe.http.router;

import std.datetime;
import std.format;

class RecipesApi
{
    DbClient client;
    ArchiveManager archiveMgr;
    PackagesApi packages;

    this(DbClient client, ArchiveManager archiveMgr, PackagesApi packages)
    {
        this.client = client;
        this.archiveMgr = archiveMgr;
        this.packages = packages;
    }

    void setupRoutes(URLRouter router)
    {
        setupRoute!GetRecipe(router, &getRecipe);
        setupRoute!PostRecipe(router, &postRecipe);
    }

    @OrderedCols
    struct Row
    {
        int id;
        string name;
        int createdBy;
        SysTime created;
        string ver;
        string revision;
        string archiveName;
        string description;
        string upstreamUrl;
        string license;
        string recipe;
        string readmeMt;
        string readme;

        RecipeResource toResource() const @safe
        {
            return RecipeResource(
                id, name, createdBy, created, ver, revision, archiveName,
                description, upstreamUrl, license, recipe, readmeMt, readme,
            );
        }
    }

    RecipeResource getRecipe(GetRecipe req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!Row(
                `
                    SELECT r.id, r.package_name, r.created_by, r.created, r.version, r.revision, a.name,
                            r.description, r.upstream_url, r.license, r.recipe, r.readme_mt, r.readme
                    FROM recipe AS r JOIN archive AS a ON a.id = r.archive_id
                    WHERE r.id = $1
                `,
                req.id
            );
            return row.toResource();
        });
    }

    NewRecipeResp postRecipe(UserInfo user, PostRecipe req) @safe
    {
        // FIXME: package name rules
        enforceStatus(
            Semver.isValid(req.ver), 400, "Invalid package version (not Semver compliant)"
        );
        enforceStatus(
            req.revision.length, 400, "Invalid package revision"
        );

        return client.transac((scope db) @safe {
            string new_;
            auto pkg = packages.createIfNotExist(db, req.name, req.description, new_);
            const recExists = db.execScalar!bool(
                `
                    SELECT count(id) <> 0 FROM recipe
                    WHERE package_name = $1 AND version = $2 AND revision = $3
                `,
                req.name, req.ver, req.revision
            );
            enforceStatus(
                !recExists, 409,
                format!"recipe %s/%s/%s already exists!"(req.name, req.ver, req.revision)
            );

            if (!new_)
            {
                const verExists = db.execScalar!bool(
                    `
                        SELECT count(id) <> 0 FROM recipe
                        WHERE package_name = $1 AND version = $2
                    `,
                    req.name, req.ver
                );
                if (!verExists)
                    new_ = "version";
            }

            const archiveName = format!"%s-%s-%s.tar.xz"(req.name, req.ver, req.revision);

            const uploadReq = archiveMgr.requestUpload(db, user.id, archiveName);

            auto recipeRow = db.execRow!Row(
                `
                    INSERT INTO recipe (
                        package_name,
                        created_by,
                        created,
                        version,
                        revision,
                        archive_id,
                        description,
                        upstream_url,
                        license
                    ) VALUES (
                        $1, $2, CURRENT_TIMESTAMP, $3, $4, $5, $6, $7, $8
                    )
                    RETURNING
                        id,
                        package_name,
                        created_by,
                        created,
                        version,
                        revision,
                        '',
                        description,
                        upstream_url,
                        license,
                        '', '', '' -- recipe and readme not known at this point
                `,
                req.name, user.id, req.ver, req.revision, uploadReq.archiveId,
                req.description, req.upstreamUrl, req.license,
            );
            recipeRow.archiveName = archiveName;

            return NewRecipeResp(
                new_, pkg, recipeRow.toResource(), uploadReq.bearerToken,
            );
        });
    }
}
