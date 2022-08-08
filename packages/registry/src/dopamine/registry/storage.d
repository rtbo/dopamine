module dopamine.storage;

import vibe.core.file;
import vibe.core.stream;
import vibe.http.common;
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
    void storeBlob(string name, InputStream blob, string sha256);
    uint blobSize(string name);
    ubyte[32] blobSha256(string name);
    InputStreamProxy getBlob(string name, uint start = 0, uint end = uint.max);
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

    void storeBlob(string name, InputStream input, string sha256) @trusted
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

        const writtenSha256 = Base64.encode(dig.finish()[]);
        if (writtenSha256 != sha256)
        {
            remove(path);
            throw new HTTPStatusException(400, "SHA256 do not match with uploaded data");
        }
    }

    uint blobSize(string name)
    {
        const path = buildPath(dir, name);
        enforce(exists(path), name ~ " doesn't exist in storage");

        return cast(uint) getSize(path);
    }

    ubyte[32] blobSha256(string name)
    {
        const path = buildPath(dir, name);
        enforce(exists(path), new HTTPStatusException(404));

        return sha256Of(read(path));
    }

    InputStreamProxy getBlob(string name, uint start, uint end) @trusted
    {
        assert(start == 0 && (end == uint.max || end == blobSize(name)), "slicing not supported");

        const path = buildPath(dir, name);
        enforce(exists(path), new HTTPStatusException(404));

        return InputStreamProxy(openFile(path));
    }
}
