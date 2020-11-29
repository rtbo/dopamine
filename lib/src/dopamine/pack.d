module dopamine.pack;

import dopamine.util;

import std.file;
import std.path;
import std.string;

interface ArchiveBackend
{
    enum archiveExt = ".tar.xz";

    /// Add all the content of [dir] (excluding [dir] itself)
    /// to the [outpath] archive.
    void create(string dir, string outpath)
    in(exists(dir) && isDir(dir) && outpath.endsWith(archiveExt));

    /// Extract all the content of [archive] into [outdir]
    /// outdir is created if does not exist.
    void extract(string archive, string outdir)
    in(exists(archive) && archive.endsWith(archiveExt));

    static ArchiveBackend get()
    {
        if (!instance)
        {
            if (findProgram("tar"))
            {
                instance = new TarArchiveBackend;
            }
            else
            {
                // TODO: 7z backend (require pack/unpack in 2 steps and to trash the intermediate .tar)
                throw new Exception("No tool to create archive on the system");
            }
        }
        return instance;
    }
}

private:

ArchiveBackend instance;

// Get all files and folder contained by dir
// No need for recursion, tar is doing it fine
// Needed because a "*" wildcard is exansed by the shell, not by tar itself.
string[] allFiles(string dir)
{
    import std.algorithm : map;
    import std.array : array;

    dir = asAbsolutePath(dir).array;
    return dirEntries(dir, SpanMode.shallow, false).map!(
            d => d.name.asRelativePath(dir).array).array;
}

class TarArchiveBackend : ArchiveBackend
{
    // TODO: check LZMA capability

    override void create(string dir, string outpath)
    {
        outpath = absolutePath(outpath);
        if (!exists(dirName(outpath)))
        {
            mkdirRecurse(dirName(outpath));
        }
        const inputs = allFiles(dir);
        runCommand(["tar", "cvJf", outpath] ~ inputs, dir);
    }

    override void extract(string archive, string outdir)
    {
        if (!exists(outdir))
        {
            mkdirRecurse(outdir);
        }
        runCommand(["tar", "xvJf", archive], outdir);
    }
}
