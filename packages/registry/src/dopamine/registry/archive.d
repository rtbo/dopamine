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

final class ArchiveManager
{
    DbClient client;
    Storage storage;

    this(DbClient client, Storage storage)
    {
        this.client = client;
        this.storage = storage;

        client.connect((scope db) {
            db.exec(`DELETE FROM archive WHERE upload_done = FALSE`);
        });
    }

    void setupRoutes(URLRouter router)
    {
        router.match(HTTPMethod.HEAD, "/archive/:name", genericHandler(&download));
        router.match(HTTPMethod.GET, "/archive/:name", genericHandler(&download));
        router.post("/archive", &upload);
    }

    UploadRequest requestUpload(scope DbConn db, int userId, string archiveName) @trusted
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
        bearerJson["aud"] = "upload";
        bearerJson["iss"] = conf.registryHostname;
        bearerJson["name"] = archiveName;
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

    void upload(scope HTTPServerRequest req, scope HTTPServerResponse resp) @safe
    {
        auto payload = enforceAuth(req);

        const id = payload["sub"].get!int;
        const aud = payload["aud"].get!string;
        const name = payload["name"].get!string;
        enforceStatus(aud == "upload", 400, "did not supply an upload token");

        string sha256 = req.headers.get("x-digest");
        enforceStatus(
            sha256 && sha256.startsWith("sha-256="),
            400, "X-Digest header with SHA256 digest is mandatory"
        );
        sha256 = sha256["sha-256=".length .. $].strip;

        client.transac((scope db) {
            const uploaded = db.execScalar!bool(`SELECT upload_done FROM archive WHERE id = $1`, id);
            enforceStatus(!uploaded, 403, "archive already uploaded");
            db.exec(`UPDATE archive SET upload_done = TRUE WHERE id = $1`, id);
        });

        try
            storage.storeBlob(name, req.bodyReader, sha256);
        catch (Exception ex)
        {
            client.connect(db => db.exec(`DELETE FROM archive WHERE id = $1`, id));
            throw ex;
        }
        resp.writeBody("");
    }

    void download(scope HTTPServerRequest req, scope HTTPServerResponse resp) @safe
    {
        string name = req.params["name"];

        @OrderedCols
        struct Info
        {
            int id;
            string name;
        }

        const info = client.connect((scope db) {
            return db.execRow!Info(
                `SELECT id, name FROM archive WHERE name = $1`,
                name
            );
        });

        if (reqWantDigestSha256(req))
        {
            const sha = storage.blobSha256(name);
            resp.headers["Digest"] = () @trusted {
                return assumeUnique("sha-256=" ~ Base64.encode(sha));
            }();
        }

        const totalLength = storage.blobSize(name);

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

        auto blob = storage.getBlob(name, start, end);

        resp.statusCode = (end - start) != totalLength ? 206 : 200;

        client.connect((scope db) => db.exec(
                `UPDATE archive SET counter = counter + 1 WHERE id = $1`,
                info.id
        ));

        pipe(blob, resp.bodyWriter);
    }
}
