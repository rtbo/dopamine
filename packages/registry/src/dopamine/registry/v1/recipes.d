module dopamine.registry.v1.recipes;

import dopamine.registry.archive;
import dopamine.registry.auth;
import dopamine.registry.db;
import dopamine.registry.utils;
import dopamine.registry.v1.packages;

import dopamine.api.v1;

import pgd.conn;

import vibe.http.router;

import std.datetime;
import std.format;

class RecipesApi
{
    DbClient client;
    ArchiveManager archiveMgr;

    this(DbClient client, ArchiveManager archiveMgr)
    {
        this.client = client;
        this.archiveMgr = archiveMgr;
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

        validateSemver(req.ver);

        enforceStatus(
            req.revision.length, 400, "Invalid package revision"
        );

        return client.transac((scope db) @safe {
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

            const pkgExists = db.execScalar!bool(
                `SELECT count(name) <> 0 FROM package WHERE name = $1`, req.name
            );

            string new_;

            if (!pkgExists)
            {
                db.exec(
                    `INSERT INTO package (name, description) VALUES ($1, $2)`,
                    req.name, req.description
                );
                new_ = "package";
            }
            else
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
                new_, recipeRow.toResource(), uploadReq.bearerToken,
            );
        });
    }
}

void validateSemver(string ver) @safe
{
    import std.regex;

    enum semverRegex = `^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)` ~
        `(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$`;
    static re = regex(semverRegex);

    auto m = enforceStatus(matchAll(ver, re), 400, format!`"%s" is not a valid Semantic Version`(ver));

    string major = m.front[1];
    string minor = m.front[2];
    string patch = m.front[3];
    string prerelease = m.front[4];

    enforceStatus(
        major.length <= 5,
        400,
        format!`"%s" is not an accepted version: major should not be more than 5 characters`(ver)
    );
    enforceStatus(
        minor.length <= 5,
        400,
        format!`"%s" is not an accepted version: minor should not be more than 5 characters`(ver)
    );
    enforceStatus(
        patch.length <= 5,
        400,
        format!`"%s" is not an accepted version: patch should not be more than 5 characters`(ver)
    );
    enforceStatus(
        prerelease.length <= 12,
        400,
        format!`"%s" is not an accepted version: patch should not be more than 10 characters`(ver)
    );
}

@("validateSemver")
unittest
{
    import unit_threaded.assertions;

    validateSemver("1.2.3-prerelease+meta");
    validateSemver("1.02.3-prerelease+meta").shouldThrow();
    validateSemver("111111.2.3-prerelease+meta").shouldThrow();
    validateSemver("1.2.3-prereleaseistoolong+meta").shouldThrow();
}
