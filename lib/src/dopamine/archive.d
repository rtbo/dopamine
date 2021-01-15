module dopamine.archive;

import dopamine.util;

import std.file;
import std.path;
import std.string;

@safe:

interface ArchiveBackend
{
    const(string)[] supportedExts();

    final bool isSupportedArchive(string filename)
    {
        import std.algorithm : endsWith;
        import std.uni : toLower;

        const lpath = filename.toLower;
        foreach (ext; supportedExts)
        {
            if (lpath.endsWith(ext))
                return true;
        }
        return false;
    }

    /// Add all the content of [dir] (excluding [dir] itself)
    /// to the [outpath] archive.
    void create(string dir, string outpath)
    in(exists(dir) && isDir(dir) && isSupportedArchive(outpath));

    /// Extract all the content of [archive] into [outdir]
    /// outdir is created if does not exist.
    void extract(string archive, string outdir)
    in(exists(archive) && isSupportedArchive(archive));

    static ArchiveBackend get()
    {
        if (!instance)
        {
            instance = new ArchiveBackendImpl;
        }
        return instance;
    }
}

private:

ArchiveBackend instance;

class ArchiveBackendImpl : ArchiveBackend
{
    bool hasTar;
    bool hasZip;

    this()
    {
        import std.exception : enforce;

        if (findProgram("tar"))
            hasTar = true;
        if (findProgram("unzip") && findProgram("zip"))
            hasZip = true;

        enforce(hasTar || hasZip, "No archive capable tool found");
    }

    // TODO: check LZMA capability
    override const(string)[] supportedExts()
    {
        const(string)[] exts = [];
        if (hasTar)
        {
            exts ~= [".tar", ".tar.gz", ".tar.bz2", ".tar.xz"];
        }
        if (hasZip)
        {
            exts ~= [".zip"];
        }
        return exts;
    }

    override void create(string dir, string outpath)
    {
        outpath = absolutePath(outpath);
        if (!exists(dirName(outpath)))
        {
            mkdirRecurse(dirName(outpath));
        }

        const inputs = allEntries(dir);

        if (outpath.endsWith(".tar"))
        {
            runCommand(["tar", "cf", outpath] ~ inputs, dir);
        }
        else if (outpath.endsWith(".tar.gz"))
        {
            runCommand(["tar", "czf", outpath] ~ inputs, dir);
        }
        else if (outpath.endsWith(".tar.bz2"))
        {
            runCommand(["tar", "cjf", outpath] ~ inputs, dir);
        }
        else if (outpath.endsWith(".tar.xz"))
        {
            runCommand(["tar", "cJf", outpath] ~ inputs, dir);
        }
        else if (outpath.endsWith(".zip"))
        {
            runCommand(["zip", "-r", outpath] ~ inputs, dir);
        }
    }

    override void extract(string archive, string outdir)
    {
        if (!exists(outdir))
        {
            mkdirRecurse(outdir);
        }

        if (archive.endsWith(".tar"))
        {
            runCommand(["tar", "xf", archive, "-C", outdir]);
        }
        else if (archive.endsWith(".tar.gz"))
        {
            runCommand(["tar", "xzf", archive, "-C", outdir]);
        }
        else if (archive.endsWith(".tar.bz2"))
        {
            runCommand(["tar", "xjf", archive, "-C", outdir]);
        }
        else if (archive.endsWith(".tar.xz"))
        {
            runCommand(["tar", "xJf", archive, "-C", outdir]);
        }
        else if (archive.endsWith(".zip"))
        {
            runCommand(["unzip", archive, "-d", outdir]);
        }
    }
}
