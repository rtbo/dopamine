module dopamine.registry.archive;

import dopamine.registry.config;
import dopamine.registry.db;
import dopamine.registry.storage;
import dopamine.registry.utils;

import jwt;
import pgd.conn;

import vibe.core.core;
import vibe.core.log;
import vibe.core.stream;
import vibe.data.json;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.wrapper;

import core.time;
import std.algorithm;
import std.base64;
import std.conv;
import std.datetime;
import std.exception;
import std.path;
import std.string;

/// Upload/download is independent of the REST API.
/// When an API need to upload an archive,
/// we return it an uploadBearer that the client uses.
struct UploadRequest
{
    int archiveId;
    string bearerToken;
}

enum ArchiveKind
{
    recipe,
}

final class ArchiveManager
{
    DbClient client;
    Storage storage;

    this(DbClient client, Storage storage)
    {
        this.client = client;
        this.storage = storage;

        // if server is stopped before upload is done,
        // invalidate it
        client.connect((scope db) {
            db.exec(`DELETE FROM archive WHERE upload_done = FALSE`);
        });
    }

    void setupRoutes(URLRouter router)
    {
        router.match(HTTPMethod.HEAD, "/archive/:name", genericHandler(&download));
        router.match(HTTPMethod.GET, "/archive/:name", genericHandler(&download));
        router.post("/archive", genericHandler(&upload));
    }

    UploadRequest requestUpload(scope DbConn db, int userId, string archiveName, ArchiveKind kind) @trusted
    {
        const int id = db.execScalar!int(
            `
                INSERT INTO archive (name, created, created_by, counter, upload_done)
                VALUES ($1, CURRENT_TIMESTAMP, $2, 0, FALSE)
                RETURNING id
            `, archiveName, userId,
        );

        const conf = Config.get;

        auto timeout = dur!"minutes"(3);

        Json bearerJson = Json.emptyObject;
        bearerJson["sub"] = id;
        bearerJson["exp"] = toJwtTime(Clock.currTime + timeout);
        bearerJson["iss"] = conf.registryHostname;
        bearerJson["name"] = archiveName;
        bearerJson["typ"] = "upload";
        bearerJson["kind"] = kind.to!string;
        const bearerToken = Jwt.sign(bearerJson, conf.registryJwtSecret);

        // if upload is still not done after timeout, we erase the archive,
        // which will will cascade to incomplete recipe or binary
        setTimer(timeout, () {
            client.connect((scope db) {
                const uploadDone = db.execScalar!bool(
                `SELECT upload_done FROM archive WHERE id = $1`, id
                );
                if (!uploadDone)
                {
                    logWarn("Cancelling upload due to expired timeout: %s", archiveName);
                    db.exec(`DELETE FROM archive WHERE id = $1`, id);
                }
            });
        });

        return UploadRequest(id, bearerToken.toString());
    }

    void upload(HTTPServerRequest req, HTTPServerResponse resp) @safe
    {
        auto payload = enforceAuth(req);

        enforceStatus(payload["typ"].opt!string == "upload", 400, "did not supply an upload token");
        const id = payload["sub"].get!int;
        const name = payload["name"].get!string;
        const kind = (payload["kind"].get!string).to!ArchiveKind;

        string sha256 = req.headers.get("x-digest");
        enforceStatus(
            sha256 && sha256.startsWith("sha-256="),
            400, "X-Digest header with SHA256 digest is mandatory"
        );
        sha256 = sha256["sha-256=".length .. $].strip;

        client.transac((scope db) {
            const uploaded = db.execScalar!bool(`SELECT upload_done FROM archive WHERE id = $1`, id);
            enforceStatus(!uploaded, 409, "archive already uploaded");
            db.exec(`UPDATE archive SET upload_done = TRUE WHERE id = $1`, id);
        });

        try
        {
            import squiz_box;

            const contentLength = req.headers["Content-Length"].to!ulong;
            enforceStatus(contentLength <= 5 * 1024 * 1024, 403, name ~ " exceeds the maximum size of 5Mb.\n" ~
                    "Consider to download the big files with the `source` function");
            storage.storeBlob(id, name, req.bodyReader, contentLength, Base64.decode(sha256));

            bool seenRecipeFile;

            auto blob = storage.getBlob(id, name);
            auto bytes = streamByteRange(blob, 1024);

            client.transac((scope db) @trusted {
                import std.stdio;
                bytes.unboxTarXz()
                    .each!(entry => writeln(entry.path));

                foreach (entry; bytes.unboxTarXz())
                {
                    if (entry.type != EntryType.regular)
                        continue;

                    db.exec(
                        `INSERT INTO archive_file (archive_id, path, size) VALUES ($1, $2, $3)`,
                        id, entry.path, cast(int)entry.size,
                    );

                    if (kind == ArchiveKind.recipe)
                    {
                        if (entry.path == "dopamine.lua")
                        {
                            auto data = cast(const(char)[])(entry.byChunk().join());
                            db.exec(
                                `UPDATE recipe SET recipe = $1 WHERE archive_id = $2`,
                                data, id,
                            );
                            seenRecipeFile = true;
                            continue;
                        }
                        const lpath = entry.path.toLower();
                        if (lpath == "readme.txt" || lpath=="readme.md" || lpath == "readme")
                        {
                            auto data = cast(const(char)[])(entry.byChunk().join());
                            db.exec(
                                `UPDATE recipe SET readme = $1, readme_filename = $2 WHERE archive_id = $3`,
                                data, entry.path, id,
                            );
                        }
                    }
                }
            });

            enforceStatus(kind != ArchiveKind.recipe || seenRecipeFile, 400, "No recipe file in uploaded archive");
        }
        catch (Exception ex)
        {
            client.connect(db => db.exec(`DELETE FROM archive WHERE id = $1`, id));
            throw ex;
        }
        resp.writeBody("");
    }

    void download(HTTPServerRequest req, HTTPServerResponse resp) @safe
    {
        string name = req.params["name"];

        const id = client.connect((scope db) {
            return db.execScalar!int(
                `SELECT id FROM archive WHERE name = $1`,
                name
            );
        });

        if (reqWantDigestSha256(req))
        {
            const sha = storage.blobSha256(id, name);
            resp.headers["Digest"] = () @trusted {
                return assumeUnique("sha-256=" ~ Base64.encode(sha));
            }();
        }

        const totalLength = storage.blobSize(id, name);

        resp.headers["Content-Disposition"] = format!"attachment; filename=%s"(name);

        uint start = 0;
        uint end = totalLength;

        if (storage.supportSlice)
        {
            auto rng = parseRangeHeader(req);
            enforceStatus(rng.length <= 1, 400, "Multi-part ranges not supported");

            const slice = rng.length ?
                rng[0].slice(totalLength) : ContentSlice(0, totalLength - 1, totalLength);
            enforceStatus(slice.last >= slice.first, 400, "Invalid range: " ~ req.headers.get(
                    "Range"));
            enforceStatus(slice.end <= totalLength, 400, "Invalid range: content bounds exceeded");

            resp.headers["Accept-Ranges"] = "bytes";
            resp.headers["Content-Range"] = format!"bytes %s-%s/%s"(slice.first, slice.last, totalLength);

            start = slice.first;
            end = slice.end;
        }
        resp.headers["Content-Length"] = (end - start).to!string;

        if (req.method == HTTPMethod.HEAD)
        {
            resp.writeVoidBody();
            return;
        }

        auto blob = storage.getBlob(id, name, start, end);

        resp.statusCode = (end - start) != totalLength ? 206 : 200;

        client.connect((scope db) => db.exec(
                `UPDATE archive SET counter = counter + 1 WHERE id = $1`,
                id
        ));

        pipe(blob, resp.bodyWriter);
    }
}
