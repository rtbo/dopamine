module dopamine.storage;

import dopamine.registry.db;
import dopamine.registry.utils;

import vibe.core.file;
import vibe.core.stream;
import vibe.http.common;
import vibe.stream.memory;
import vibe.stream.wrapper;

import std.base64;
import std.digest.sha;
import std.exception;
import std.file;
import std.path;
import std.range;
import std.stdio;

@safe:

interface Storage
{
    bool supportSlice();
    void storeBlob(int id, string name, InputStream blob, ulong len, const(ubyte)[] sha256);
    uint blobSize(int id, string name);
    ubyte[32] blobSha256(int id, string name);
    InputStreamProxy getBlob(int id, string name, uint start = 0, uint end = uint.max);
}

final class FileSystemStorage : Storage
{
    string dir;

    this(string dir)
    {
        enforce(
            exists(dir) && isDir(dir),
            "FileSystemStorage: no such directory: " ~ dir
        );
        this.dir = dir;
    }

    bool supportSlice()
    {
        return false;
    }

    void storeBlob(int id, string name, InputStream input, ulong len, const(ubyte)[] sha256) @trusted
    {
        import std.algorithm : copy;

        const path = buildPath(dir, name);
        enforce(!exists(path), name ~ " is already in storage");

        auto dig = makeDigest!SHA256();

        {
            auto file = File(path, "wb");

            streamInputRange!8192(input)
                .tee(&dig)
                .copy(file.lockingBinaryWriter);
        }

        const writtenSha256 = dig.finish();
        if (writtenSha256 != sha256)
        {
            remove(path);
            throw new HTTPStatusException(400, "SHA256 do not match with uploaded data");
        }
    }

    uint blobSize(int id, string name)
    {
        const path = buildPath(dir, name);
        enforce(exists(path), name ~ " doesn't exist in storage");

        return cast(uint) getSize(path);
    }

    ubyte[32] blobSha256(int id, string name)
    {
        const path = buildPath(dir, name);
        enforce(exists(path), new HTTPStatusException(404));

        return sha256Of(read(path));
    }

    InputStreamProxy getBlob(int id, string name, uint start, uint end) @trusted
    {
        assert(start == 0 && (end == uint.max || end == blobSize(id, name)), "slicing not supported");

        const path = buildPath(dir, name);
        enforce(exists(path), new HTTPStatusException(404));

        return InputStreamProxy(openFile(path));
    }
}

final class DatabaseStorage : Storage
{
    DbClient client;

    this (DbClient client)
    {
        this.client = client;
    }

    bool supportSlice()
    {
        return false;
    }

    void storeBlob(int id, string name, InputStream blob, ulong len, const(ubyte)[] sha256)
    {
        auto buf = new ubyte[len];
        blob.read(buf);
        client.transac((scope db) {
            const writtenSha256 = db.execScalar!(const(ubyte)[])(
                `
                    INSERT INTO archive(data) VALUES($1) WHERE id = $2
                    RETURNING sha256(data)
                `, buf, id
            );
            enforceStatus(writtenSha256 == sha256, 400, "SHA256 do not match with uploaded data");
        });
    }

    uint blobSize(int id, string name)
    {
        return client.connect(db => db.execScalar!uint(`SELECT length(data) FROM archive WHERE id = $1`, id));
    }

    ubyte[32] blobSha256(int id, string name)
    {
        return client.connect(db => db.execScalar!(ubyte[32])(`SELECT sha256(data) FROM archive WHERE id = $1`, id));
    }

    InputStreamProxy getBlob(int id, string name, uint start = 0, uint end = uint.max)
    {
        assert(start == 0 && (end == uint.max || end == blobSize(id, name)), "slicing not supported");

        ubyte[] data = client.connect(db => db.execScalar!(ubyte[])(`SELECT data FROM archive WHERE id = $1`, id));
        return InputStreamProxy(createMemoryStream(data, false));
    }
}
