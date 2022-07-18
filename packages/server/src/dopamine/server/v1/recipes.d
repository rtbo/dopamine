module dopamine.server.v1.recipes;

import dopamine.server.auth;
import dopamine.server.db;
import dopamine.server.utils;

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

    this(DbClient client)
    {
        this.client = client;
    }

    void setupRoutes(URLRouter router)
    {
        setupRoute!GetPackage(router, &getPackage);
        setupRoute!PostRecipe(router, &postRecipe);
        setupRoute!GetLatestRecipeRevision(router, &getLatestRecipeRevision);
        setupRoute!GetRecipeRevision(router, &getRecipeRevision);
        setupRoute!GetRecipe(router, &getRecipe);
        setupRoute!GetRecipeFiles(router, &getRecipeFiles);
        setupDownloadRoute!DownloadRecipeArchive(router, &downloadRecipeArchive);
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
        string recipe;

        RecipeResource toResource() const @safe
        {
            return RecipeResource(
                id, ver, revision, recipe, maintainerId, created.toUTC()
            );
        }
    }

    RecipeResource getLatestRecipeRevision(GetLatestRecipeRevision req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!RecipeRow(
                `
                    SELECT "id", "maintainer_id", "created", "version", "revision", "recipe"
                    FROM "recipe" WHERE
                        "package_name" = $1 AND
                        "version" = $2
                    ORDER BY "created" DESC
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
                    SELECT "id", "maintainer_id", "created", "version", "revision", "recipe"
                    FROM "recipe" WHERE
                        "package_name" = $1 AND
                        "version" = $2 AND
                        "revision" = $3
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
                    SELECT "id", "maintainer_id", "created", "version", "revision", "recipe"
                    FROM "recipe" WHERE "id" = $1
                `,
                req.id
            );
            return row.toResource();
        });
    }

    const(RecipeFile)[] getRecipeFiles(GetRecipeFiles req) @safe
    {
        return client.connect((scope DbConn db) {
            return db.execRows!RecipeFile(
                `SELECT "name", "size" FROM "recipe_file" WHERE "recipe_id" = $1`, req.id,
            );
        });
    }

    void downloadRecipeArchive(scope HTTPServerRequest req, scope HTTPServerResponse resp) @safe
    {
        const id = convParam!int(req, "id");

        auto rng = parseRangeHeader(req);
        enforceStatus(rng.length <= 1, 400, "Multi-part ranges not supported");

        @OrderedCols
        static struct Info
        {
            string pkgName;
            string ver;
            string revision;
            uint totalLength;
        }

        const info = client.connect(db => db.execRow!Info(
                `SELECT package_name, version, revision, length(archive_data) FROM recipe WHERE id = $1`,
                id
        ));
        const totalLength = info.totalLength;

        resp.headers["Content-Disposition"] = format!"attachment; filename=%s-%s-%s.tar.xz"(
            info.pkgName, info.ver, info.revision
        );

        if (reqWantDigestSha256(req))
        {
            const sha = client.connect(db => db.execScalar!(ubyte[32])(
                    `SELECT sha256(archive_data) FROM recipe WHERE id = $1`,
                    id,
            ));
            resp.headers["Digest"] = () @trusted {
                return assumeUnique("sha-256=" ~ Base64.encode(sha));
            }();
        }

        resp.headers["Accept-Ranges"] = "bytes";

        const slice = rng.length ?
            rng[0].slice(totalLength) : ContentSlice(0, totalLength - 1, totalLength);
        enforceStatus(slice.last >= slice.first, 400, "Invalid range: " ~ req.headers.get("Range"));
        enforceStatus(slice.end <= totalLength, 400, "Invalid range: content bounds exceeded");

        resp.headers["Content-Length"] = slice.sliceLength.to!string;
        if (rng.length)
            resp.headers["Content-Range"] = format!"bytes %s-%s/%s"(slice.first, slice.last, totalLength);

        if (req.method == HTTPMethod.HEAD)
        {
            resp.writeVoidBody();
            return;
        }

        const(ubyte)[] data;
        if (rng.length)
        {
            data = client.connect((scope db) {
                // substring index is one based
                return db.execScalar!(const(ubyte)[])(
                    `SELECT substring(archive_data FROM $1 FOR $2) FROM recipe WHERE id = $3`,
                    slice.first + 1, slice.sliceLength, id,
                );
            });
            resp.statusCode = 206;
        }
        else
        {
            data = client.connect((scope db) {
                return db.execScalar!(const(ubyte)[])(
                    `SELECT archive_data FROM recipe WHERE id = $1`, id,
                );
            });
        }
        enforce(slice.sliceLength == data.length, "No match of data length and content length");

        resp.writeBody(data);
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

    RecipeFile[] checkAndReadRecipeArchive(const(ubyte)[] archiveData,
        const(ubyte)[] archiveSha256,
        out string recipe) @trusted
    {
        enum szLimit = 1 * 1024 * 1024;

        enforceStatus(
            archiveData.length <= szLimit, 400,
            "Recipe archive is too big. Ensure to not leave unneeded data."
        );

        const sha256 = sha256Of(archiveData);
        enforceStatus(
            sha256[] == archiveSha256, 400, "Could not verify archive integrity (invalid SHA256 checksum)"
        );

        RecipeFile[] files;
        auto entries = only(archiveData)
            .decompressXz()
            .readTarArchive();

        bool seenRecipe;
        foreach (e; entries)
        {
            enforceStatus(!e.isBomb(10 * szLimit), 400, "Archive bomb detected!");

            if (e.path == "dopamine.lua")
            {
                enforceStatus(e.size <= szLimit, 400, "dopamine.lua file is too big!");
                recipe = cast(string) e.byChunk().join().idup;
                seenRecipe = true;
            }
            files ~= RecipeFile(e.path, cast(uint) e.size);
        }
        enforceStatus(
            seenRecipe, 400, "Recipe archive do not contain dopamine.lua file"
        );
        return files;
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

        const archiveSha256 = Base64.decode(req.archiveSha256);
        const archive = Base64.decode(req.archive);

        string recipe;
        auto files = checkAndReadRecipeArchive(archive, archiveSha256, recipe);

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

            const recipeRow = db.execRow!RecipeRow(
                `
                    INSERT INTO recipe (
                        package_name,
                        maintainer_id,
                        created,
                        version,
                        revision,
                        recipe,
                        archive_data
                    ) VALUES (
                        $1, $2, CURRENT_TIMESTAMP, $3, $4, $5, $6
                    )
                    RETURNING
                        id,
                        maintainer_id,
                        created,
                        version,
                        revision,
                        recipe
                `, req.name, user.id, req.ver, req.revision, recipe, archive
            );

            const doubleCheck = db.execScalar!(const(ubyte)[])(
                `SELECT digest(archive_data, 'sha256') FROM recipe WHERE id = $1`, recipeRow.id
            );
            enforce(doubleCheck == archiveSha256, "Could not verify archive integrity after insert");

            foreach (f; files)
                db.exec(
                    `INSERT INTO recipe_file (recipe_id, name, size) VALUES ($1, $2, $3)`,
                    recipeRow.id, f.name, f.size
                );
            return NewRecipeResp(
                newPkg, pkg, recipeRow.toResource()
            );
        });
    }
}