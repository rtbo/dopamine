module dopamine.registry.v1.recipes;

import dopamine.registry.archive;
import dopamine.registry.auth;
import dopamine.registry.db;
import dopamine.registry.utils;

import dopamine.api.attrs;
import dopamine.api.v1;
import dopamine.semver;

import pgd.conn;

import squiz_box;

import vibe.http.common;
import vibe.http.router;
import vibe.http.server;

import std.base64;
import std.conv;
import std.datetime.systime;
import std.digest.sha;
import std.exception;
import std.format;
import std.range;

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
        setupRoute!GetPackage(router, &getPackage);
        setupRoute!PostRecipe(router, &postRecipe);
        setupRoute!GetLatestRecipeRevision(router, &getLatestRecipeRevision);
        setupRoute!GetRecipeRevision(router, &getRecipeRevision);
        setupRoute!GetRecipe(router, &getRecipe);
    }

    @OrderedCols
    static struct PackRow
    {
        string name;
        int maintainerId;
        SysTime created;

        PackageResource toResource(string[] versions) const @safe
        {
            return PackageResource(name, maintainerId, created.toUTC(), versions);
        }
    }

    PackageResource getPackage(GetPackage req) @safe
    {
        return client.connect((scope DbConn db) @safe {
            const row = db.execRow!PackRow(
                `SELECT "name", "maintainer_id", "created" FROM "package" WHERE "name" = $1`,
                req.name
            );
            auto vers = db.execScalars!string(
                `SELECT DISTINCT "version" FROM "recipe" WHERE "package_name" = $1`,
                row.name,
            );
            // sorting descending order (latest versions first)
            import std.algorithm : sort;

            vers.sort!((a, b) => Semver(a) > Semver(b));
            return row.toResource(vers);
        });
    }

    @OrderedCols
    static struct RecipeRow
    {
        int id;
        int maintainerId;
        SysTime created;
        string ver;
        string revision;
        string archiveName;

        RecipeResource toResource() const @safe
        {
            return RecipeResource(
                id, ver, revision, maintainerId, created.toUTC(), archiveName
            );
        }
    }

    RecipeResource getLatestRecipeRevision(GetLatestRecipeRevision req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!RecipeRow(
                `
                    SELECT r.id, r.maintainer_id, r.created, r.version, r.revision, a.name
                    FROM recipe AS r JOIN archive AS a ON a.id = r.archive_id
                    WHERE
                        r.package_name = $1 AND
                        r.version = $2
                    ORDER BY r.created DESC
                    LIMIT 1
                `,
                req.name, req.ver,
            );
            return row.toResource();
        });
    }

    RecipeResource getRecipeRevision(GetRecipeRevision req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!RecipeRow(
                `
                    SELECT r.id, r.maintainer_id, r.created, r.version, r.revision, a.name
                    FROM recipe AS r JOIN archive AS a ON a.id = r.archive_id
                    WHERE
                        r.package_name = $1 AND
                        r.version = $2 AND
                        r.revision = $3
                `,
                req.name, req.ver, req.revision,
            );
            return row.toResource();
        });
    }

    RecipeResource getRecipe(GetRecipe req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!RecipeRow(
                `
                    SELECT r.id, r.maintainer_id, r.created, r.version, r.revision, a.name
                    FROM recipe AS r JOIN archive AS a ON a.id = r.archive_id
                    WHERE r.id = $1
                `,
                req.id
            );
            return row.toResource();
        });
    }

    PackageResource createPackageIfNotExist(scope DbConn db, int userId, string packName, out bool newPkg) @safe
    {
        auto prows = db.execRows!PackRow(
            `SELECT name, maintainer_id, created FROM package WHERE name = $1`, packName
        );
        string[] vers;
        newPkg = prows.length == 0;
        if (prows.length == 0)
        {
            prows = db.execRows!PackRow(
                `
                    INSERT INTO package (name, maintainer_id, created)
                    VALUES ($1, $2, CURRENT_TIMESTAMP)
                    RETURNING name, maintainer_id, created
                `,
                packName, userId
            );
        }
        else
        {
            import std.algorithm : sort;

            vers = db.execScalars!string(
                `SELECT version FROM recipe WHERE package_name = $1`, packName
            );
            vers.sort!((a, b) => Semver(a) > Semver(b));
        }
        return prows[0].toResource(vers);
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
            bool newPkg;
            auto pkg = createPackageIfNotExist(db, user.id, req.name, newPkg);
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

            const archiveName = format!"%s-%s-%s.tar.xz"(req.name, req.ver, req.revision);

            const uploadReq = archiveMgr.requestUpload(db, user.id, archiveName);

            auto recipeRow = db.execRow!RecipeRow(
                `
                    INSERT INTO recipe (
                        package_name,
                        maintainer_id,
                        created,
                        version,
                        revision,
                        archive_id
                    ) VALUES (
                        $1, $2, CURRENT_TIMESTAMP, $3, $4, $5
                    )
                    RETURNING
                        id,
                        maintainer_id,
                        created,
                        version,
                        revision,
                        ''
                `, req.name, user.id, req.ver, req.revision, uploadReq.archiveId
            );
            recipeRow.archiveName = archiveName;

            return NewRecipeResp(
                newPkg, pkg, recipeRow.toResource(), uploadReq.bearerToken,
            );
        });
    }
}
