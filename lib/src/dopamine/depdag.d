/// Dependency Directed Acyclic Graph
///
/// This a kind of hybrid graph with the following abstractions:
/// - [DepPack]: correspond to a package and gathers several versions
/// - [DepNode]: correspond to a package version, that express dependencies towards other packages
/// - [DepEdge]: correspond to a dependency specification.
///
/// Edges start from a [DepNode] and points towards a [DepPack] and hold a [VersionSpec] that
/// is used during resolution to select the resolved [DepNode] within pointed [DepPack]
///
/// The directions up and down used in this module refer to the following
/// - The DAG root is at the top. This is the package for which dependencies are resolved
/// - The DAG leaves are at the bottom. These are the dependencies that do not have dependencies themselves.
module dopamine.depdag;

import dopamine.dependency;
import dopamine.recipe;
import dopamine.semver;

/// Interface for an object that interacts with repository and/or local package cache
/// Implementation may be cache-only or cache+network
/// Implementation may also be a test mock.
interface CacheRepo
{
    /// Get the recipe of a package in its specified version
    /// Params:
    ///     packname = name of the package
    ///     ver = version of the package
    /// Returns: The recipe of the package
    /// Throws: ServerDownException, NoSuchPackageException, NoSuchPackageVersionException
    const(Recipe) packRecipe(string packname, const(Semver) ver) @safe;

    /// Get the available versions of a package
    /// Params:
    ///     packname = name of the package
    /// Returns: the list of versions available of the package
    /// Throws: ServerDownException, NoSuchPackageException
    Semver[] packAvailVersions(string packname) @safe;

    /// Check whether a package version is in local cache or not
    /// Params:
    ///     packname = name of the package
    ///     ver = version of the package
    /// Retruns: whether the package is in local cache
    bool packIsCached(string packname, const(Semver) ver) @safe;
}

/// Heuristics to help choosing a package version in a set of compatible versions
enum Heuristics
{
    /// Will pick the highest compatible version that is in local cache, and revert to network if none is found
    preferCached,
    /// Will always pick the highest compatible version regardless if it is cached or not
    pickHighest,
}

/// Dependency DAG package : represent a package and gathers DAG nodes, each of which is a version of this package
class DepPack
{
    /// Name of the package
    string name;

    /// The available versions of the package
    Semver[] allVersions;

    /// The version nodes of the package that are compabile with the current state of the DAG.
    /// Starts with the full list of available versions and reduces during resolution.
    DepNode[] nodes;

    /// The resolved version node
    DepNode resolvedNode;

    /// Edges towards packages that depends on this
    DepEdge[] upEdges;

    this(string name, Semver[] allVersions) @safe
    in(isStrictlyMonotonic(allVersions))
    {
        import std.algorithm : map;
        import std.array : array;

        this.name = name;
        this.allVersions = allVersions;
        nodes = allVersions.map!(v => new DepNode(this, v)).array;
    }

    /// The versions of the package that are compabile with the current state of the DAG.
    /// Starts with the full list of available versions and reduces during resolution.
    @property const(Semver)[] compatibleVersions() const @safe pure
    {
        import std.algorithm : map;
        import std.array : array;

        return nodes.map!(n => n.ver).array;
    }

    /// Get node that match with [ver]
    DepNode getNode(const(Semver) ver) @safe
    {
        foreach (n; nodes)
        {
            if (n.ver == ver)
                return n;
        }
        return null;
    }

    /// Removes nodes whose version do not match with [spec]
    /// and clean-up connected edges
    private void filterVersions(VersionSpec spec) @trusted
    {
        import std.algorithm : remove;

        size_t i;
        while (i < nodes.length)
        {
            if (spec.matchVersion(nodes[i].ver))
            {
                i++;
                continue;
            }

            // must remove this version, as well as clean-up up-edges
            // in lower nodes
            foreach (de; nodes[i].downEdges)
            {
                de.down.upEdges = de.down.upEdges.remove!(e => e == de);
            }

            // no increment as size is reduced
            nodes = nodes.remove(i);
        }
    }

    /// Remove node matching with ver.
    /// Do not perform any cleanup in up/down edges
    private void removeNode(Semver ver) @safe
    {
        import std.algorithm : remove;

        nodes = nodes.remove!(n => n.ver == ver);
    }
}

/// Actual DAG node, that correspond to a version of a package
class DepNode
{
    /// The package owner of this version node
    DepPack pack;

    /// The package version
    Semver ver;

    /// The edges going to dependencies of this package
    DepEdge[] downEdges;

    this(DepPack pack, Semver ver) @safe
    {
        this.pack = pack;
        this.ver = ver;
    }

    bool isResolved() const @trusted
    {
        return pack.resolvedNode is this;
    }
}

/// Dependency DAG edge : represent a dependency and its associated version requirement
/// [up] has a dependency towards [down] with [spec]
class DepEdge
{
    DepNode up;
    DepPack down;
    VersionSpec spec;

    /// Create a dependency edge between a package version and another package
    static DepEdge create(DepNode up, DepPack down, VersionSpec spec) @safe
    {
        auto res = new DepEdge;

        res.up = up;
        res.down = down;
        res.spec = spec;

        up.downEdges ~= res;
        down.upEdges ~= res;

        return res;
    }

    bool onResolvedPath() const @safe
    {
        return up.isResolved && down.resolvedNode !is null;
    }
}

/// Prepare a dependency DAG for package described by [recipe]
/// The construction of the DAG is made in top-down direction (from the root
/// package down to its dependencies.
DepPack prepareDepDAG(const(Recipe) recipe, CacheRepo cacheRepo) @safe
{
    import std.algorithm : canFind, filter, map, sort;
    import std.array : array;
    import std.exception : enforce;

    DepPack[string] packs;

    DepPack prepPack(string name) @safe
    {
        if (auto p = name in packs)
            return *p;

        auto av = cacheRepo.packAvailVersions(name);
        sort(av);

        auto pack = new DepPack(name, av);

        packs[name] = pack;

        return pack;
    }

    DepNode[] visited;
    DepPack root = new DepPack(recipe.name, [recipe.ver]);

    void doPackVersion(DepPack pack, const(Semver) ver) @trusted
    {
        auto node = pack.getNode(ver);
        assert(node);

        if (visited.canFind(node))
            return;

        visited ~= node;

        const recipe = pack is root ? recipe : cacheRepo.packRecipe(pack.name, ver);

        foreach (dep; recipe.dependencies)
        {
            auto dp = prepPack(dep.name);

            DepEdge.create(node, dp, dep.spec);

            foreach (v; dp.compatibleVersions)
            {
                doPackVersion(dp, v);
            }
        }
    }

    doPackVersion(root, recipe.ver);

    return root;
}

/// Collect all leaves from a graph, that is nodes without leaving edges
DepPack[] collectDAGLeaves(DepPack root) @safe
{
    import std.algorithm : canFind;

    DepPack[] traversed;
    DepPack[] leaves;

    void collectLeaves(DepPack pack) @trusted
    {
        if (traversed.canFind(pack))
            return;
        traversed ~= pack;

        bool isLeaf = true;
        foreach (n; pack.nodes)
        {
            foreach (e; n.downEdges)
            {
                collectLeaves(e.down);
                isLeaf = false;
            }
        }
        if (isLeaf)
        {
            leaves ~= pack;
        }
    }

    collectLeaves(root);

    return leaves;
}

/// Traverse the graph from top to bottom  and apply [dg] for
/// every package on the way
void traversePacksTopDown(DepPack root, void delegate(DepPack) @safe dg) @safe
{
    import std.algorithm : canFind;

    DepPack[] traversed;

    void traverse(DepPack pack) @trusted // canFind is @system
    {
        if (traversed.canFind(pack))
            return;
        traversed ~= pack;

        dg(pack);

        foreach (n; pack.nodes)
            foreach (e; n.downEdges)
                traverse(e.down);
    }

    traverse(root);
}

/// Traverse the graph from bottom to top and apply [dg] for
/// every package on the way.
/// In order to traverse in this direction, the tree is traversed once
/// in top down direction in order to collect the leaves
void traversePacksBottomUp(DepPack root, void delegate(DepPack) @safe dg) @safe
{
    import std.algorithm : canFind;

    DepPack[] traversed;

    void traverse(DepPack pack) @trusted // canFind is @system
    {
        if (traversed.canFind(pack))
            return;
        traversed ~= pack;

        dg(pack);

        foreach (e; pack.upEdges)
            traverse(e.up.pack);
    }

    auto leaves = collectDAGLeaves(root);
    foreach (l; leaves)
        traverse(l);
}

/// Traverse the graph from top to bottom and apply [dg]
/// on every resolved node found on the way.
void traverseResolvedNodesTopDown(DepPack root, void delegate(DepNode) @safe dg) @safe
{
    import std.algorithm : canFind;

    traversePacksTopDown(root, (DepPack pack) @safe {
        if (pack.resolvedNode)
            dg(pack.resolvedNode);
    });
}

/// Traverse the graph from top to bottom and apply [dg]
/// on every resolved node found on the way.
void traverseResolvedNodesBottomUp(DepPack root, void delegate(DepNode) @safe dg) @safe
{
    import std.algorithm : canFind;

    traversePacksBottomUp(root, (DepPack pack) @safe {
        if (pack.resolvedNode)
            dg(pack.resolvedNode);
    });
}

/// Finalize filtering of incompatible versions in the DAG
/// This is done by successive up traversals until nothing changes
void checkDepDAGCompat(DepPack root) @safe
{
    import std.algorithm : any, canFind, filter, remove;

    // compatibility check in bottom-up direction
    // returns whether some version was removed during traversal

    while (1)
    {
        bool diff;
        traversePacksBottomUp(root, (DepPack pack) @trusted {
            if (pack == root)
                return;
            // Remove nodes of pack for which at least one up package is found
            // without compatibility with it
            DepPack[] ups;
            foreach (e; pack.upEdges)
            {
                if (!ups.canFind(e.up.pack))
                {
                    ups ~= e.up.pack;
                }
            }

            size_t ni;
            while (ni < pack.nodes.length)
            {
                bool rem;

                auto n = pack.nodes[ni];
                foreach (up; ups)
                {
                    const compat = pack.upEdges
                        .filter!(e => e.up.pack == up)
                        .any!(e => e.spec.matchVersion(n.ver));
                    if (!compat)
                    {
                        rem = true;
                        break;
                    }
                }

                if (rem)
                {
                    diff = true;
                    pack.removeNode(n.ver);
                    foreach (e; n.downEdges)
                    {
                        e.down.upEdges = e.down.upEdges.remove!(ue => ue == e);
                    }
                }
                else
                {
                    ni++;
                }
            }
        });

        if (!diff)
            break;
    }
}

/// Resolves a DAG such as each package has a resolved version
void resolveDepDAG(DepPack root, CacheRepo cacheRepo, Heuristics heuristics)
out(; dagIsResolved(root))
{
    void resolveDeps(DepPack pack)
    in(pack.resolvedNode)
    {
        foreach (e; pack.resolvedNode.downEdges)
        {
            if (e.down.resolvedNode)
                continue;

            const resolved = chooseVersion(heuristics, cacheRepo, e.down.name,
                    e.down.compatibleVersions);

            foreach (n; e.down.nodes)
            {
                if (n.ver == resolved)
                {
                    e.down.resolvedNode = n;
                    break;
                }
            }
            resolveDeps(e.down);
        }
    }

    root.resolvedNode = root.nodes[0];
    resolveDeps(root);
}

/// Check whether a DAG is fully resolved
bool dagIsResolved(DepPack root) @safe
{
    bool resolved = true;

    traversePacksTopDown(root, (p) @safe {
        if (p.resolvedNode is null)
            resolved = false;
    });

    return resolved;
}

/// Serialize a resolved DAG to lock-file content
string dagToLockFile(DepPack root, bool emitAllVersions = true) @safe
in(emitAllVersions || dagIsResolved(root))
{
    // using own writing logic because std.json do not preserve any field
    // ordering

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

    traversePacksTopDown(root, (DepPack pack) @trusted {
        line("");
        line("package: %s", pack.name);

        foreach (v; pack.allVersions)
        {
            indent++;
            scope (success)
                indent--;

            auto n = pack.getNode(v);

            if (n is null && !emitAllVersions)
                continue;

            string attr;
            if (n is null)
            {
                attr = " [excluded]";
            }
            else if (n is pack.resolvedNode)
            {
                attr = " [resolved]";
            }

            line("version: %s%s", v, attr);

            if (n !is null)
            {
                foreach (e; n.downEdges)
                {
                    indent++;
                    scope (success)
                        indent--;

                    line("dependency: %s %s", e.down.name, e.spec);
                }
            }
        }
    });

    return w.data;
}

/// Serialize a resolved DAG to a lock-file
void dagToLockFile(DepPack root, string filename, bool emitAllVersions = true) @safe
{
    import std.file : write;

    const content = dagToLockFile(root, emitAllVersions);
    write(filename, content);
}

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
DepPack dagFromLockFileContent(string content, string filename = null) @safe
{
    import std.algorithm : map;
    import std.array : split;
    import std.conv : to;
    import std.exception : enforce;
    import std.string : endsWith, indexOf, lineSplitter, startsWith, strip;

    struct Ver
    {
        string pack;
        Semver ver;
        bool resolved;
        bool excluded;
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

    string[] packs;
    Ver[] vers;
    Dep[] deps;

    int line;
    foreach (l; lineSplitter(content).map!(l => l.strip()))
    {
        enum lockfilemark = "# dop lock-file v";
        enum pmark = "package: ";
        enum vmark = "version: ";
        enum dmark = "dependency: ";
        enum resolvedmark = " [resolved]";
        enum excludedmark = " [excluded]";

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
                bool excluded;
                if (l.endsWith(resolvedmark))
                {
                    resolved = true;
                    l = l[0 .. $ - resolvedmark.length];
                }
                else if (l.endsWith(excludedmark))
                {
                    excluded = true;
                    l = l[0 .. $ - excludedmark.length];
                }
                curver = Semver(l);
                seenver = true;
                vers ~= Ver(curpack, curver, resolved, excluded);
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

        auto pack = new DepPack(p, allVers);

        foreach (v; vers[0 .. count])
        {
            if (v.resolved)
            {
                pack.resolvedNode = pack.getNode(v.ver);
            }
            else if (v.excluded)
            {
                pack.removeNode(v.ver);
            }
        }
        vers = vers[count .. $];

        depacks[p] = pack;
        if (root is null)
            root = pack;
    }

    foreach (d; deps)
    {
        auto up = depacks[d.pack].getNode(d.ver);
        auto down = depacks[d.down];
        DepEdge.create(up, down, d.spec);
    }

    return root;
}

/// Deserialize DAG from lock-file [filename]
DepPack dagFromLockFile(string filename) @trusted
{
    import std.file : read;
    import std.exception : assumeUnique;

    const content = cast(string) assumeUnique(read(filename));
    return dagFromLockFileContent(content, filename);
}

/// Issue a GraphViz' Dot representation of a DAG
string dagToDot(DepPack root) @safe
{
    import std.algorithm : find;
    import std.array : appender, replicate;
    import std.format : format;
    import std.string : join;

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

    void block(string header, void delegate() @safe dg) @safe
    {
        line(header ~ " {");
        indent += 1;
        dg();
        indent -= 1;
        line("}");
    }

    string[string] packGNames;
    uint packNum = 1;
    string[string] nodeGNames;
    uint nodeNum = 1;

    string nodeId(string packname, const(Semver) ver) @safe
    {
        return format("%s-%s", packname, ver);
    }

    string nodeGName(string packname, const(Semver) ver) @safe
    {
        const id = nodeId(packname, ver);
        const res = nodeGNames[id];
        assert(res, "unprocessed version: " ~ id);
        return res;
    }

    block("digraph G", {
        line("");
        line("graph [compound=true ranksep=1];");
        line("");

        // write clusters / pack

        traversePacksTopDown(root, (DepPack pack) @safe {
            const name = format("cluster_%s", packNum++);
            packGNames[pack.name] = name;

            const(Semver)[] allVersions = pack.allVersions;
            const(Semver)[] compatVersions = pack.compatibleVersions;

            block("subgraph " ~ name, {

                line("label = \"%s\";", pack.name);
                line("node [shape=box];");

                foreach (v; allVersions)
                {
                    const nid = nodeId(pack.name, v);
                    const ngn = format("ver_%s", nodeNum++);
                    nodeGNames[nid] = ngn;

                    const compat = compatVersions.find(v).length > 0;
                    string style = "dashed";
                    string color = "";
                    if (pack.resolvedNode && pack.resolvedNode.ver == v)
                    {
                        style = `"filled,solid"`;
                        color = ", color=teal";
                    }
                    else if (compat)
                    {
                        style = `"filled,solid"`;
                    }

                    line(`%s [label="%s", style=%s%s];`, ngn, v, style, color);
                }
            });
            line("");

        });

        // write all edges

        traversePacksTopDown(root, (DepPack pack) @safe {
            foreach (n; pack.nodes)
            {
                const ngn = nodeGName(pack.name, n.ver);
                foreach (e; n.downEdges)
                {
                    // if down pack has a resolved version, we point to it directly
                    // otherwise we point to subgraph (the pack).

                    // To point to a subgraph, we still must point to a particular node
                    // in the subgraph and specify lhead
                    // we pick the last highest version in an arbitrary way
                    // it makes the arrows point towards it, but stop at the subgraph border

                    auto downNode = e.down.resolvedNode
                    ? e.down.resolvedNode.ver : e.down.compatibleVersions[$ - 1];
                    const downNgn = nodeGName(e.down.name, downNode);

                    string head = "";
                    if (!e.onResolvedPath)
                    {
                        const downPgn = packGNames[e.down.name];
                        assert(ngn, "unprocessed package: " ~ ngn);
                        head = "lhead=" ~ downPgn ~ " ";
                    }
                    // space around label to provide some margin
                    line(`%s -> %s [%slabel=" %s  "];`, ngn, downNgn, head, e.spec);
                }
            }
        });
    });

    return w.data;
}

/// Write Graphviz' dot representation of a DAG to [filename]
void dagToDot(DepPack root, string filename) @safe
{
    import std.file : write;

    const dot = dagToDot(root);
    write(filename, dot);
}

@("Test general graph utility")
unittest
{
    import std.algorithm : canFind;

    auto cacheRepo = TestCacheRepo.withBase();

    auto dag = prepareDepDAG("e", Semver("1.0.0"), cacheRepo);

    auto leaves = collectDAGLeaves(dag);
    assert(leaves.length == 1);
    assert(leaves[0].name == "a");

    string[] names;
    traversePacksTopDown(dag, (p) @safe { names ~= p.name; });
    assert(names.length == 5);
    assert(names[0] == "e");
    assert(names.canFind("a", "b", "c", "d", "e"));

    names = null;
    traversePacksBottomUp(dag, (p) @safe { names ~= p.name; });
    assert(names.length == 5);
    assert(names[0] == "a");
    assert(names.canFind("a", "b", "c", "d", "e"));

    checkDepDAGCompat(dag);
    resolveDepDAG(dag, cacheRepo, Heuristics.preferCached);

    names = null;
    traverseResolvedNodesTopDown(dag, (n) @safe { names ~= n.pack.name; });
    assert(names.length == 5);
    assert(names[0] == "e");
    assert(names.canFind("a", "b", "c", "d", "e"));

    names = null;
    traverseResolvedNodesBottomUp(dag, (n) @safe { names ~= n.pack.name; });
    assert(names.length == 5);
    assert(names[0] == "a");
    assert(names.canFind("a", "b", "c", "d", "e"));
}

@("Test Heuristic.preferCached")
unittest
{
    auto cacheRepo = TestCacheRepo.withBase();

    auto dag = prepareDepDAG("e", Semver("1.0.0"), cacheRepo);
    checkDepDAGCompat(dag);
    resolveDepDAG(dag, cacheRepo, Heuristics.preferCached);

    Semver[string] resolvedVersions;
    traverseResolvedNodesTopDown(dag, (n) @safe {
        resolvedVersions[n.pack.name] = n.ver;
    });

    assert(resolvedVersions["a"] == "1.1.0");
    assert(resolvedVersions["b"] == "0.0.1");
    assert(resolvedVersions["c"] == "2.0.0");
    assert(resolvedVersions["d"] == "1.1.0");
    assert(resolvedVersions["e"] == "1.0.0");
}

@("Test Heuristic.pickHighest")
unittest
{
    auto cacheRepo = TestCacheRepo.withBase();

    auto dag = prepareDepDAG("e", Semver("1.0.0"), cacheRepo);
    checkDepDAGCompat(dag);
    resolveDepDAG(dag, cacheRepo, Heuristics.pickHighest);

    Semver[string] resolvedVersions;
    traverseResolvedNodesTopDown(dag, (n) @safe {
        resolvedVersions[n.pack.name] = n.ver;
    });

    assert(resolvedVersions["a"] == "2.0.0");
    assert(resolvedVersions["b"] == "0.0.2");
    assert(resolvedVersions["c"] == "2.0.0");
    assert(resolvedVersions["d"] == "1.1.0");
    assert(resolvedVersions["e"] == "1.0.0");
}

@("Test Serialization")
unittest
{
    auto cacheRepo = TestCacheRepo.withBase();

    auto dag1 = prepareDepDAG("e", Semver("1.0.0"), cacheRepo);
    checkDepDAGCompat(dag1);
    resolveDepDAG(dag1, cacheRepo, Heuristics.pickHighest);

    const lock = dagToLockFile(dag1, true);
    auto dag2 = dagFromLockFileContent(lock);

    assert(lock == dagToLockFile(dag2, true));
    assert(dagToDot(dag1) == dagToDot(dag2));
}

private:

import std.algorithm : isStrictlyMonotonic;

/// Choose a compatible versions according heuristics
/// Compatible versions MUST be sorted
const(Semver) chooseVersion(Heuristics heuristics, CacheRepo cacheRepo,
        string packname, const(Semver)[] compatibleVersions) @safe
in(compatibleVersions.length > 0 && isStrictlyMonotonic(compatibleVersions))
{
    // shortcut if no choice
    if (compatibleVersions.length == 1)
        return compatibleVersions[0];

    final switch (heuristics)
    {
    case Heuristics.preferCached:
        foreach_reverse (const ref v; compatibleVersions)
        {
            if (cacheRepo.packIsCached(packname, v))
                return v;
        }
        goto case;
    case Heuristics.pickHighest:
        return compatibleVersions[$ - 1];
    }
}

version (unittest)
{
    struct TestPackVersion
    {
        string ver;
        Dependency[] deps;
        bool cached;
    }

    struct TestPackage
    {
        string name;
        TestPackVersion[] nodes;
    }

    TestPackage[] buildTestPackBase(TestPackage e)
    {
        auto a = TestPackage("a", [
                TestPackVersion("1.0.0", [], true),
                TestPackVersion("1.1.0", [], true), TestPackVersion("1.1.1"),
                TestPackVersion("2.0.0"),
                ]);

        auto b = TestPackage("b", [
                TestPackVersion("0.0.1", [
                        Dependency("a", VersionSpec(">=1.0.0 <2.0.0"))
                    ], true),
                TestPackVersion("0.0.2", [
                        Dependency("a", VersionSpec(">=1.1.0"))
                    ]),
                ]);

        auto c = TestPackage("c", [
                TestPackVersion("1.0.0", [], true),
                TestPackVersion("2.0.0", [
                        Dependency("a", VersionSpec(">=1.1.0"))
                    ]),
                ]);
        auto d = TestPackage("d", [
                TestPackVersion("1.0.0", [Dependency("c", VersionSpec("1.0.0"))], true),
                TestPackVersion("1.1.0", [Dependency("c", VersionSpec("2.0.0"))]),
                ]);
        return [a, b, c, d, e];
    }

    TestPackage[] buildTestPackBase()
    {
        return buildTestPackBase(TestPackage("e", [
                    TestPackVersion("1.0.0", [
                        Dependency("b", VersionSpec(">=0.0.1")),
                        Dependency("d", VersionSpec(">=1.1.0")),
                    ])
                ]));
    }

    /// A mock CacheRepo
    final class TestCacheRepo : CacheRepo
    {
        TestPackage[string] packs;

        this(TestPackage[] packs)
        {
            foreach (p; packs)
            {
                this.packs[p.name] = p;
            }
        }

        static TestCacheRepo withBase(TestPackage e)
        {
            return new TestCacheRepo(buildTestPackBase(e));
        }

        static TestCacheRepo withBase()
        {
            return new TestCacheRepo(buildTestPackBase());
        }

        /// Get the dependencies of a package in its specified version
        Dependency[] packDeps(string packname, const(Semver) ver) @safe
        {
            import std.algorithm : find;
            import std.exception : enforce;
            import std.range : front;

            return packs[packname].nodes.find!(pv => pv.ver == ver).front.deps;
        }

        /// Get the available versions of a package
        Semver[] packAvailVersions(string packname) @safe
        {
            import std.algorithm : map;
            import std.array : array;

            return packs[packname].nodes.map!(pv => Semver(pv.ver)).array;
        }

        /// Check whether a package version is in local cache or not
        bool packIsCached(string packname, const(Semver) ver) @safe
        {
            import std.algorithm : find;
            import std.range : front;

            return packs[packname].nodes.find!(pv => pv.ver == ver).front.cached;
        }
    }
}
