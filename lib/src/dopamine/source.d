module dopamine.source;

import dopamine.paths;
import dopamine.util;

import std.file;
import std.json;
import std.path;
import std.string;

@safe:

interface Source
{
    string fetch(in string dest) const

    in(isDir(dest))
    out(res; res.startsWith(dest) && isDir(res));

    static bool fetchNeeded(PackageDir packageDir)
    {
        auto flagFile = packageDir.sourceFlag();
        if (!flagFile.exists)
            return true;
        const sourceDir = flagFile.read();
        if (!exists(sourceDir) || !isDir(sourceDir))
            return true;
        return flagFile.timeLastModified > timeLastModified(packageDir.dopamineFile());
    }

    /// print out JSON recipe representation
    JSONValue toJson() const;
}

class GitSource : Source
{
    private string _url;
    private string _revId;
    private string _subdir;

    this(string url, string revId, string subdir)
    {
        import dopamine.util : findProgram;
        import std.exception : enforce;

        enforce(findProgram("git"), "could not find git in PATH!");
        enforce(url.length, "Repo URL must be provided");
        enforce(revId.length, "Revision ID must be provided");

        _url = url;
        _revId = revId;
        _subdir = subdir;
    }

    override string fetch(in string dest) const
    {
        import dopamine.util : runCommand;
        import std.algorithm : endsWith;
        import std.exception : enforce;
        import std.process : pipeProcess, Redirect;

        auto dirName = urlLastComp(_url);
        if (dirName.endsWith(".git"))
        {
            dirName = dirName[0 .. $ - 4];
        }

        const srcDir = buildPath(dest, dirName);
        if (!exists(srcDir))
        {
            runCommand(["git", "clone", _url, dirName], dest, false);
        }

        enforce(isDir(srcDir));

        runCommand(["git", "checkout", _revId], srcDir, false);

        return _subdir ? buildPath(srcDir, _subdir) : srcDir;
    }

    override JSONValue toJson() const
    {
        JSONValue json;
        json["type"] = "source";
        json["method"] = "git";
        json["url"] = _url;
        json["revId"] = _revId;
        if (_subdir)
        {
            json["subdir"] = _subdir;
        }
        return json;
    }
}

struct Checksum
{
    import std.digest : Digest;

    enum Type
    {
        md5,
        sha1,
        sha256,
    }

    Type type;
    string checksum;

    void enforceFileCheck(const string filename) const @trusted
    in(checksum.length)
    {
        import std.exception : enforce;

        enforce(fileCheck(filename), format(`"%s" didn't check to "%s"`, filename, checksum));
    }

    bool fileCheck(const string filename) const @trusted
    {
        import std.digest : toHexString, LetterCase;
        import std.stdio : File, writeln;

        auto digest = createDigest();
        ubyte[4096] buf = void;

        auto f = File(filename, "rb");
        size_t sum = 0;
        foreach (c; f.byChunk(buf[]))
        {
            sum += c.length;
            digest.put(c);
        }

        writeln("checked ", sum, " bytes");

        const res = digest.finish().toHexString!(LetterCase.lower)();
        return res == checksum.toLower();
    }

    private Digest createDigest() const
    {
        import std.digest.md : MD5Digest;
        import std.digest.sha : SHA1Digest, SHA256Digest;

        final switch (type)
        {
        case Checksum.Type.md5:
            return new MD5Digest;
        case Checksum.Type.sha1:
            return new SHA1Digest;
        case Checksum.Type.sha256:
            return new SHA256Digest;
        }
    }

    private bool opCast(T : bool)() const
    {
        return checksum.length != 0;
    }
}

class ArchiveSource : Source
{
    private string _url;
    private Checksum _checksum;

    this(string url, Checksum checksum = Checksum.init)
    {
        _url = url;
        _checksum = checksum;
    }

    override string fetch(in string dest) const @trusted
    {
        import std.file : exists, isDir;
        import std.path : buildPath;
        import std.uri : decode;

        const decoded = decode(_url);
        const fn = urlLastComp(decoded);
        const archive = buildPath(dest, fn);

        const ldn = likelySrcDirName(archive);
        if (exists(ldn) && isDir(ldn))
        {
            return ldn;
        }

        downloadArchive(archive);
        return extractArchive(archive, dest);

    }

    override JSONValue toJson() const
    {
        import std.conv : to;

        JSONValue json;
        json["type"] = "source";
        json["method"] = "archive";
        json["url"] = _url;
        if (_checksum)
        {
            const key = _checksum.type.to!string;
            json[key] = _checksum.checksum;
        }
        return json;
    }

    private void downloadArchive(in string archive) const @trusted
    {
        import std.exception : enforce;
        import std.file : exists, remove;
        import std.net.curl : download;
        import std.stdio : writefln;

        if (!exists(archive) || !(_checksum && _checksum.fileCheck(archive)))
        {
            if (exists(archive))
            {
                remove(archive);
            }

            writefln("downloading %s", _url);
            download(_url, archive);

            if (_checksum)
                _checksum.enforceFileCheck(archive);
        }
    }

    private string extractArchive(in string archive, in string dest) const
    {
        import dopamine.archive : ArchiveBackend;
        import dopamine.util : allEntries;
        import std.algorithm : count, filter, map;
        import std.array : array;

        ArchiveBackend.get.extract(archive, dest);

        // check whether the archive contained a dir or all files at root
        const entries = allEntries(dest).map!(e => buildPath(dest, e))
            .filter!(e => e != archive)
            .array;
        if (entries.length == 1 && isDir(entries[0]))
        {
            return entries[0];
        }
        else
        {
            return dest;
        }
    }
}

private string urlLastComp(in string url)
in(url.length > 0)
{
    import std.exception : enforce;
    import std.format : format;
    import std.string : lastIndexOf;
    import std.uri : decode;

    const pi = lastIndexOf(url, '/');
    enforce(pi != -1, format(`"%s" does not appear to be a valid URL`, url));
    enforce(pi != cast(ptrdiff_t) url.length - 1,
            format(`"%s" does not appear to be a valid URL`, url));

    const comp = url[pi + 1 .. $];

    const qi = lastIndexOf(comp, '?');

    return decode(qi == -1 ? comp : comp[0 .. qi]);
}

unittest
{
    assert(urlLastComp("https://github.com/rtbo/dopamine.git") == "dopamine.git");
    assert(urlLastComp("http://some-site.test/archive-name.tar.gz?q=param") == "archive-name.tar.gz");
}

private string likelySrcDirName(in string archive)
{
    import dopamine.archive : ArchiveBackend;

    import std.algorithm : endsWith;
    import std.uni : toLower;

    foreach (ext; ArchiveBackend.get.supportedExts)
    {
        if (archive.toLower.endsWith(ext))
        {
            return archive[0 .. $ - ext.length];
        }
    }
    assert(false);
}

unittest
{
    assert(likelySrcDirName("/path/archivename.tar.gz") == "/path/archivename");
}
