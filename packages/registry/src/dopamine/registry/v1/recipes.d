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
        setupRoute!GetPackageLatestRecipe(router, &getPackageLatestRecipe);
        setupRoute!GetPackageRecipe(router, &getPackageRecipe);

        setupRoute!GetRecipe(router, &getRecipe);
        setupRoute!PostRecipe(router, &postRecipe);
    }

    @OrderedCols
    static struct PackRow
    {
        string name;
        string description;

        PackageResource toResource(string[] versions) const @safe
        {
            return PackageResource(name, description, versions);
        }
    }

    PackageResource getPackage(GetPackage req) @safe
    {
        import std.algorithm : sort;

        return client.connect((scope DbConn db) @safe {
            const row = db.execRow!PackRow(
                `SELECT name, description FROM package WHERE name = $1`,
                req.name
            );
            auto vers = db.execScalars!string(
                `SELECT DISTINCT version FROM recipe WHERE package_name = $1`,
                row.name,
            );

            // sorting descending order (latest versions first)
            vers.sort!((a, b) => Semver(a) > Semver(b));
            return row.toResource(vers);
        });
    }

    @OrderedCols
    static struct PkgRevRow
    {
        int recipeId;
        string name;
        string ver;
        string revision;
        string archiveName;
        string description;

        PackageRecipeResource toResource() const @safe
        {
            return PackageRecipeResource(
                name, ver, revision, recipeId, archiveName, description,
            );
        }
    }

    PackageRecipeResource getPackageLatestRecipe(GetPackageLatestRecipe req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!PkgRevRow(
                `
                    SELECT r.id, r.package_name, r.version, r.revision, a.name, r.description
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

    PackageRecipeResource getPackageRecipe(GetPackageRecipe req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!PkgRevRow(
                `
                    SELECT r.id, r.package_name, r.version, r.revision, a.name, r.description
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

    @OrderedCols
    struct RecipeRow
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
            const row = db.execRow!RecipeRow(
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

    PackageResource createPackageIfNotExist(scope DbConn db, PostRecipe req, out string new_) @safe
    {
        auto prows = db.execRows!PackRow(
            `SELECT name, description FROM package WHERE name = $1`, req.name
        );
        string[] vers;
        if (prows.length == 0)
        {
            new_ = "package";

            prows = db.execRows!PackRow(
                `
                    INSERT INTO package (name, description)
                    VALUES ($1, $2)
                    RETURNING name, description
                `,
                req.name, req.description
            );
        }
        else
        {
            import std.algorithm : sort;

            assert(prows.length == 1);

            vers = db.execScalars!string(
                `SELECT version FROM recipe WHERE package_name = $1`, req.name
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
            string new_;
            auto pkg = createPackageIfNotExist(db, req, new_);
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

            auto recipeRow = db.execRow!RecipeRow(
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
