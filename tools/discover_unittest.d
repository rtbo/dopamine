module tools.discover_unittest;

import std.algorithm;
import std.array;
import std.getopt;
import std.file;
import std.path;
import std.stdio;
import std.string;

string processFile(string filename)
{
    string mod;
    auto file = File(filename, "r");
    foreach (l; file.byLine.map!(l => l.strip))
    {
        // reasonable assumption about how module is defined
        if (!mod && l.startsWith("module ") && l.endsWith(";"))
        {
            mod = l["module ".length .. $ - 1].strip().idup;
            continue;
        }
        if (mod && l.canFind("unittest"))
        {
            return mod;
        }
    }
    return null;
}

int main(string[] args)
{
    string root = ".";
    string modname = "test.all_mods";
    string[] exclusions;

    auto helpInfo = getopt(args, "root", &root, "exclude", &exclusions, "modname", &modname);
    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("Discover unittest files.", helpInfo.options);
        return 0;
    }

    string[] mods;

    string[] dFiles = args[1 .. $];
    if (args.length == 0)
    {
        dFiles = dirEntries(root, SpanMode.depth).filter!(f => f.name.endsWith(".d"))
            .map!(e => e.name)
            .array;
    }

    outer: foreach (f; dFiles)
    {
        foreach (ex; exclusions)
        {
            if (f.canFind(ex))
                continue outer;
        }

        const m = processFile(f);
        if (m)
        {
            mods ~= m;
        }
    }

    mods = mods.sort().uniq().array;

    writefln("module %s;", modname);
    writefln("");
    writefln("import std.meta : AliasSeq;");
    writefln("");
    foreach (m; mods)
    {
        writefln("import %s;", m);
    }
    writefln("");
    writefln("alias allModules = AliasSeq!(");
    foreach (m; mods)
    {
        writefln("    %s,", m);
    }
    writefln(");");

    return 0;
}
