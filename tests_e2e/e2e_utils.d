module e2e_utils;

import std.array;
import std.exception;
import std.file;
import std.format;
import std.path;
import std.stdio;
import std.typecons;

string e2ePath(Args...)(Args args)
{
    return buildNormalizedPath(dirName(__FILE_FULL_PATH__), args);
}

void copyRecurse(string src, string dest)
in (exists(src) && isDir(src))
in (!exists(dest) || !isFile(dest))
{
    mkdirRecurse(dest);

    foreach (e; dirEntries(src, SpanMode.breadth))
    {
        const relative = relativePath(e.name, src);
        const path = buildPath(dest, relative);

        if (e.isDir)
            mkdir(path);
        else
            copy(e.name, path);
    }
}

// expand env vars of shape $VAR or ${VAR}
string expandEnvVars(string input, string[string] environment)
{
    import std.algorithm : canFind;
    import std.ascii : isAlphaNum;

    string result;

    string var;
    bool env;
    bool mustach;

    void expand()
    {
        string val = *enforce(var in environment, format!"Could not find %s in sandbox environment"(var));
        result ~= val;
        var = null;
        env = false;
        mustach = false;
    }

    foreach (dchar c; input)
    {
        if (env && !mustach)
        {
            if (isAlphaNum(c) || c == '_')
                var ~= c;
            else if (var.length == 0 && c == '{')
                mustach = true;
            else
            {
                expand();
                result ~= c;
            }
        }
        else if (env && mustach)
        {
            if (c == '}')
                expand();
            else
                var ~= c;
        }
        else if (c == '$')
        {
            env = true;
        }
        else
        {
            result ~= c;
        }
    }

    if (env)
        expand();

    return result;
}

void reportFileContent(File report, string filePath, string label, int headLen = 80)
{
    if (label.length > headLen)
        label = label[0 .. headLen - 4] ~ " ...";
    else if (label.length < headLen - 1)
        label ~= " " ~ "-".replicate(headLen - label.length - 1);
    else if (label.length < headLen)
        label ~= " ";

    assert(label.length == headLen);

    report.writeln(label);
    foreach (l; File(filePath, "r").byLine(Yes.keepTerminator))
        report.write(l);
    report.writeln("-".replicate(headLen));
}

/// Search for filename in the envPath variable content which can
/// contain multiple paths separated with sep depending on platform.
/// Returns: null if the file can't be found.
string searchInEnvPath(in string envPath, in string filename, in string sep = pathSeparator)
{
    import std.algorithm : splitter;

    foreach (dir; splitter(envPath, sep))
    {
        const filePath = buildPath(dir, filename);
        if (exists(filePath))
            return filePath;
    }
    return null;
}
