/// Module to read and write dependency lock files
module dopamine.deplock;

import dopamine.depdag;
import dopamine.dependency;
import dopamine.profile;
import dopamine.semver;

import std.typecons;

/// Serialize a resolved DAG to lock-file content
string dagToLockFile(DepDAG dag, bool emitAllVersions = true) @safe
in(emitAllVersions || dagIsResolved(dag))
{
    import std.algorithm : map;
    import std.array : appender, join, replicate;
    import std.format : format;

    auto w = appender!string;
    int indent = 0;

    void line(Args...)(string lfmt, Args args) @safe
    {
        static if (Args.length == 0)
        {
            w.put(replicate("  ", indent) ~ lfmt ~ "\n");
        }
        else
        {
            w.put(replicate("  ", indent) ~ format(lfmt, args) ~ "\n");
        }
    }

    line("# AUTO GENERATED FILE - DO NOT EDIT!!!");
    line("# dop lock-file v1");
    line("");
    line("heuristics: %s", dag.heuristics);

    foreach (pack; dag.traverseTopDown(Yes.root))
    {
        line("");
        line("package: %s", pack.name);

        indent++;
        scope (success)
            indent--;

        foreach (v; pack.allVersions)
        {
            auto n = pack.getNode(v);

            if (n is null && !emitAllVersions)
                continue;

            string attr;
            if (n && n is pack.resolvedNode)
            {
                attr = " [resolved]";
            }
            else if (n)
            {
                attr = " [considered]";
            }

            line("version: %s%s", v, attr);

            if (n !is null)
            {
                indent++;
                scope (success)
                    indent--;

                if (n.revision)
                {
                    line("revision: %s", n.revision);
                }

                if (n.langs.length)
                {
                    line("langs: %s", n.langs.strFromLangs().join(", "));
                }
                foreach (e; n.downEdges)
                {
                    line("dependency: %s %s", e.down.name, e.spec);
                }
            }
        }
    }

    return w.data;
}

/// Serialize a resolved DAG to a lock-file
void dagToLockFile(DepDAG dag, string filename, bool emitAllVersions = true) @safe
{
    import std.file : write;

    const content = dagToLockFile(dag, emitAllVersions);
    write(filename, content);
}

/// Exception thrown when reading invalid lock-file
class InvalidLockFileException : Exception
{
    string filename;
    int line;
    string reason;

    this(string filename, int line, string reason) @safe
    {
        import std.format : format;

        this.filename = filename;
        this.line = line;
        this.reason = reason;

        const fn = filename ? filename ~ ":" : "lock-file:";
        super(format("%s(%s): Error: invalid lock-file - %s", fn, line, reason));
    }
}

/// Deserialize a lock-file content to a DAG
///
/// Params:
///     content: the content of a lock-file
///     filename: optional filename for error reporting
/// Returns: The deserialized DAG
DepDAG dagFromLockFileContent(string content, string filename = null) @safe
{
    import std.algorithm : map;
    import std.array : array, split;
    import std.conv : to;
    import std.exception : enforce;
    import std.string : endsWith, indexOf, lineSplitter, startsWith, strip;

    struct Ver
    {
        string pack;
        Semver ver;
        bool resolved;
        bool considered;
    }

    struct Rev
    {
        string pack;
        Semver ver;
        string revision;
    }

    struct Lng
    {
        string pack;
        Semver ver;
        Lang[] langs;
    }

    struct Dep
    {
        string pack;
        Semver ver;
        string down;
        VersionSpec spec;
    }

    string curpack;
    Semver curver;
    bool seenver;

    Heuristics heuristics;
    string[] packs;
    Ver[] vers;
    Rev[] revs;
    Lng[] langs;
    Dep[] deps;

    int line;
    foreach (l; lineSplitter(content).map!(l => l.strip()))
    {
        enum lockfilemark = "# dop lock-file v";
        enum hmark = "heuristics: ";
        enum pmark = "package: ";
        enum vmark = "version: ";
        enum rmark = "revision: ";
        enum lmark = "langs: ";
        enum dmark = "dependency: ";
        enum resolvedmark = " [resolved]";
        enum consideredmark = " [considered]";

        line++;

        try
        {
            if (l.startsWith(lockfilemark))
            {
                l = l[lockfilemark.length .. $];
                enforce(l.to!int == 1, new InvalidLockFileException(filename,
                        line, "Unsupported lock-file version " ~ l));
            }
            else if (l.length == 0 || l.startsWith('#'))
            {
                continue;
            }
            else if (l.startsWith(hmark))
            {
                const h = l[hmark.length .. $];
                switch (h)
                {
                case "preferCached":
                    heuristics = Heuristics.preferCached;
                    break;
                case "pickHighest":
                    heuristics = Heuristics.pickHighest;
                    break;
                default:
                    throw new InvalidLockFileException(filename, line, "unknown heuristics: " ~ h);
                }
            }
            else if (l.startsWith(pmark))
            {
                curpack = l[pmark.length .. $];
                seenver = false;
                packs ~= curpack;
            }
            else if (l.startsWith(vmark))
            {
                enforce(curpack, new InvalidLockFileException(filename, line,
                        "Ill-formed lock-file"));
                l = l[vmark.length .. $];
                bool resolved;
                bool considered;
                if (l.endsWith(resolvedmark))
                {
                    resolved = true;
                    l = l[0 .. $ - resolvedmark.length];
                }
                else if (l.endsWith(consideredmark))
                {
                    considered = true;
                    l = l[0 .. $ - consideredmark.length];
                }
                curver = Semver(l);
                seenver = true;
                vers ~= Ver(curpack, curver, resolved, considered);
            }
            else if (l.startsWith(rmark))
            {
                enforce(curpack && seenver, new InvalidLockFileException(filename,
                        line, "Ill-formed lock-file"));
                revs ~= Rev(curpack, curver, l[rmark.length .. $]);
            }
            else if (l.startsWith(lmark))
            {
                enforce(curpack && seenver, new InvalidLockFileException(filename,
                        line, "Ill-formed lock-file"));
                l = l[lmark.length .. $];
                auto entries = l.split(',').map!(l => l.strip()).array;
                langs ~= Lng(curpack, curver, strToLangs(entries));
            }
            else if (l.startsWith(dmark))
            {
                enforce(curpack && seenver, new InvalidLockFileException(filename,
                        line, "Ill-formed lock-file"));

                l = l[dmark.length .. $];
                const splt = indexOf(l, " ");
                enforce(l.length >= 3 && splt > 0 && splt < l.length - 1, // @suppress(dscanner.suspicious.length_subtraction)
                        new InvalidLockFileException(filename, line, "Can't parse dependency"));

                deps ~= Dep(curpack, curver, l[0 .. splt], VersionSpec(l[splt + 1 .. $]));
            }
            else
            {
                throw new InvalidLockFileException(filename, line, "Unexpected input: " ~ l);
            }
        }
        catch (InvalidSemverException ex)
        {
            throw new InvalidLockFileException(filename, line, ex.msg);
        }
        catch (InvalidVersionSpecException ex)
        {
            throw new InvalidLockFileException(filename, line, ex.msg);
        }
    }

    DepPack[string] depacks;
    DepPack root;

    foreach (p; packs)
    {
        Semver[] allVers;

        // all structs are ordered, so we can always expect match at start of vers and none after
        uint count;
        foreach (v; vers)
        {
            if (v.pack == p)
            {
                allVers ~= v.ver;
                count++;
            }
            else
            {
                break;
            }
        }

        auto pack = new DepPack(p);
        pack.allVersions = allVers;

        foreach (v; vers[0 .. count])
        {
            if (v.resolved || v.considered)
            {
                auto n = pack.getOrCreateNode(v.ver);
                if (v.resolved)
                    pack.resolvedNode = n;
            }
        }
        vers = vers[count .. $];

        depacks[p] = pack;
        if (root is null)
            root = pack;
    }

    foreach (r; revs)
    {
        auto node = depacks[r.pack].getNode(r.ver);
        node.revision = r.revision;
    }

    foreach (l; langs)
    {
        auto node = depacks[l.pack].getNode(l.ver);
        node.langs = l.langs;
    }

    foreach (d; deps)
    {
        auto up = depacks[d.pack].getNode(d.ver);
        auto down = depacks[d.down];
        DepEdge.create(up, down, d.spec);
    }

    return DepDAG(root, heuristics);
}

DepDAG dagFromLockFile(string filename) @trusted
{
    import std.exception : assumeUnique;
    import std.file : read;

    string content = cast(string)assumeUnique(read(filename));
    return dagFromLockFileContent(content, filename);
}

@("Test Lock-file serialization")
unittest
{
    import test.profile : ensureDefaultProfile;

    auto cacheRepo = TestCacheRepo.withBase();

    auto recipe = packE.recipe("1.0.0");
    auto profile = ensureDefaultProfile();

    auto dag1 = prepareDepDAG(recipe, profile, cacheRepo, Heuristics.pickHighest);
    // checkDepDAGCompat(dag1);
    resolveDepDAG(dag1, cacheRepo);
    dagFetchLanguages(dag1, recipe, cacheRepo);

    const lock = dagToLockFile(dag1, true);
    auto dag2 = dagFromLockFileContent(lock);

    assert(lock == dagToLockFile(dag2, true));
    assert(dagToDot(dag1) == dagToDot(dag2));
}
