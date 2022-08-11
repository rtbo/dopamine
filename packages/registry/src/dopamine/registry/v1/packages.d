module dopamine.registry.v1.packages;

import dopamine.registry.db;
import dopamine.registry.utils;

import dopamine.api.v1;
import dopamine.semver;

import pgd.conn;

import vibe.http.router;

class PackagesApi
{
    DbClient client;

    this(DbClient client)
    {
        this.client = client;
    }

    void setupRoutes(URLRouter router)
    {
        setupRoute!GetPackage(router, &get);
        setupRoute!GetPackageLatestRecipe(router, &getLatestRecipe);
        setupRoute!GetPackageRecipe(router, &getRecipe);
    }

    @OrderedCols
    static struct Row
    {
        string name;
        string description;

        PackageResource toResource(string[] versions) const @safe
        {
            return PackageResource(name, description, versions);
        }
    }

    PackageResource get(GetPackage req) @safe
    {
        import std.algorithm : sort;

        return client.connect((scope DbConn db) @safe {
            const row = db.execRow!Row(
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
    static struct PkgRecipeRow
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

    PackageRecipeResource getLatestRecipe(GetPackageLatestRecipe req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!PkgRecipeRow(
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

    PackageRecipeResource getRecipe(GetPackageRecipe req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!PkgRecipeRow(
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

    PackageResource createIfNotExist(scope DbConn db, string name, string description, out string new_) @safe
    {
        auto prows = db.execRows!Row(
            `SELECT name, description FROM package WHERE name = $1`, name
        );
        string[] vers;
        if (prows.length == 0)
        {
            new_ = "package";

            prows = db.execRows!Row(
                `
                    INSERT INTO package (name, description)
                    VALUES ($1, $2)
                    RETURNING name, description
                `,
                name, description
            );
        }
        else
        {
            import std.algorithm : sort;

            assert(prows.length == 1);

            vers = db.execScalars!string(
                `SELECT version FROM recipe WHERE package_name = $1`, name
            );
            vers.sort!((a, b) => Semver(a) > Semver(b));
        }
        return prows[0].toResource(vers);
    }
}
