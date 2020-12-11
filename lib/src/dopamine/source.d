module dopamine.source;

@safe:

interface Source
{
    string fetch(in string dest);
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

    override string fetch(in string dest)
    {
        import dopamine.util : runCommand;
        import std.algorithm : endsWith;
        import std.exception : enforce;
        import std.file : exists, isDir;
        import std.path : buildPath;
        import std.process : pipeProcess, Redirect;
        import std.uri : decode;

        const decoded = decode(_url);
        auto dirName = urlLastComp(decoded);

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

        return srcDir;
    }
}

private enum ArchiveFormat
{
    targz,
    tar,
    zip,
}

private immutable(string[]) supportedArchiveExts = [".zip", ".tar.gz", ".tar"];

private bool isSupportedArchiveExt(in string path)
{
    import std.algorithm : endsWith;
    import std.uni : toLower;

    const lpath = path.toLower;
    foreach (ext; supportedArchiveExts)
    {
        if (lpath.endsWith(ext))
            return true;
    }
    return false;
}

private ArchiveFormat archiveFormat(in string path)
in (isSupportedArchiveExt(path))
{
    import std.algorithm : endsWith;
    import std.uni : toLower;

    const lpath = path.toLower;

    if (lpath.endsWith(".zip"))
        return ArchiveFormat.zip;
    if (lpath.endsWith(".tar.gz"))
        return ArchiveFormat.targz;
    if (lpath.endsWith(".tar"))
        return ArchiveFormat.tar;

    assert(false);
}

private string urlLastComp(in string url)
in(url.length > 0)
{
    size_t ind = url.length - 1;
    while (ind >= 0 && url[ind] != '/')
    {
        ind--;
    }
    return url[ind + 1 .. $];
}

private string likelySrcDirName(in string archive)
in(isSupportedArchiveExt(archive))
{
    import std.algorithm : endsWith;
    import std.uni : toLower;

    foreach (ext; supportedArchiveExts)
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
