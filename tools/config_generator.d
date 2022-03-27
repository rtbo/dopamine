/// Script that prints the meson version if it is matching
/// the current tag or the commit id
module tools.config_generator;

import std.exception;
import std.getopt;
import std.path;
import std.process;
import std.regex;
import std.stdio;
import std.string;

enum dopRoot = buildNormalizedPath(__FILE_FULL_PATH__.dirName.dirName);

string mesonVersion()
{
    const verRe = regex(`version\s*:\s*'(.+)'`);
    const mainMesonScript = buildPath(dopRoot, "meson.build");
    foreach (l; File(mainMesonScript, "r").byLine())
    {
        const m = matchFirst(l, verRe);
        if (!m)
            continue;
        return m[1].idup;
    }
    throw new Exception("could not read the version from meson.build");
}

string commandOutput(string[] cmd, string workDir = null)
{
    const res = execute(cmd, null, Config.none, size_t.max, workDir);
    if (res.status != 0)
    {
        const msg = format("command `%s` failed with code %s:\n%s", escapeShellCommand(cmd), res.status, res
                .output);
        throw new Exception(msg);
    }
    return res.output.strip();
}

string gitLastTag()
{
    const res = execute(["git", "describe", "--tags", "--abbrev=0"], null, Config.none, size_t.max, dopRoot);
    if (res.status == 0)
    {
        return res.output.strip();
    }
    return null;
}

string gitCurrentCommit()
{
    return commandOutput(["git", "log", "-n", "1", "--pretty=format:%H"], dopRoot);
}

bool gitDirty()
{
    return commandOutput(["git", "status", "--porcelain"]).length > 0;
}

int main(string[] args)
{
    try
    {
        string input;
        string output;

        auto opt = getopt(args,
            "input", &input,
            "output", &output,
        );

        if (opt.helpWanted)
        {
            defaultGetoptPrinter("Dopamine configuration generator", opt.options);
            return 0;
        }

        const mv = mesonVersion();
        const glt = gitLastTag();
        const dirty = gitDirty();

        string dopVersion = mv;
        string dopBuildId = mv;

        if (mv != glt)
        {
            const commit = gitCurrentCommit();
            dopBuildId = commit[0 .. 8];
        }
        if (dirty)
        {
            dopBuildId ~= "-dirty";
        }

        auto inp = File(input, "r");
        auto outp = File(output, "w");


        foreach (l; inp.byLineCopy())
        {
            const lin = l
                .replace("@DOP_VERSION@", dopVersion)
                .replace("@DOP_BUILD_ID@", dopBuildId);
            outp.writeln(lin);
        }

        return 0;
    }
    catch (Exception ex)
    {
        stderr.writeln(ex.msg);
        return 1;
    }
}
