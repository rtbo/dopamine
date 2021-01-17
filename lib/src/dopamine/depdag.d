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
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

import std.typecons;

/// Interface for an object that interacts with repository and/or local package cache
/// Implementation may be cache-only or cache+network
/// Implementation may also be a test mock.
interface CacheRepo
{
    /// Get the recipe of a package in its specified version
    /// Params:
    ///     packname = name of the package
    ///     ver = version of the package
    ///     revision = optional revision of the package
    /// Returns: The recipe of the package
    /// Throws: ServerDownException, NoSuchPackageException, NoSuchPackageVersionException
    Recipe packRecipe(string packname, Semver ver, string revision = null) @safe;

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
    ///     revision = optional revision of the package
    /// Retruns: whether the package is in local cache
    bool packIsCached(string packname, Semver ver, string revision = null) @safe;
}

/// Heuristics to help choosing a package version in a set of compatible versions
enum Heuristics
{
    /// Will pick the highest compatible version that is in local cache, and revert to network if none is found
    preferCached,
    /// Will always pick the highest compatible version regardless if it is cached or not
    pickHighest,
}

/// Dependency graph
struct DepDAG
{
    package DepPack root;
    package Heuristics heuristics;

    auto traverseTopDown(Flag!"root" traverseRoot = No.root) @safe
    {
        auto res = DepthFirstTopDownRange([root]);

        if (!traverseRoot)
            res.popFront();

        return res;
    }

    auto traverseBottomUp(Flag!"root" traverseRoot = No.root) @safe
    {
        auto res = DepthFirstBottomUpRange(collectLeaves());

        if (!traverseRoot)
            res.visited ~= root;

        return res;
    }

    auto traverseTopDownResolved(Flag!"root" traverseRoot = No.root) @safe
    {
        import std.algorithm : filter, map;

        return traverseTopDown(traverseRoot).filter!(p => (p.resolvedNode !is null))
            .map!(p => p.resolvedNode);
    }

    auto traverseBottomUpResolved(Flag!"root" traverseRoot = No.root) @safe
    {
        import std.algorithm : filter, map;

        return traverseBottomUp(traverseRoot).filter!(p => (p.resolvedNode !is null))
            .map!(p => p.resolvedNode);
    }

    /// Collect all leaves from a graph, that is nodes without leaving edges
    DepPack[] collectLeaves() @safe
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
}

/// Dependency DAG package : represent a package and gathers DAG nodes, each of which is a version of this package
class DepPack
{
    /// Name of the package
    string name;

    /// The available versions of the package that are compatible with the current state of the DAG.
    Semver[] allVersions;

    /// The version nodes of the package that are considered for the resolution.
    /// This is a subset of allVersions
    DepNode[] nodes;

    /// The resolved version node
    DepNode resolvedNode;

    /// Edges towards packages that depends on this
    DepEdge[] upEdges;

    package this(string name) @safe
    {
        this.name = name;
    }

    /// Get node that match with [ver]
    /// Create one if doesn't exist
    package DepNode getOrCreateNode(const(Semver) ver) @safe
    {
        foreach (n; nodes)
        {
            if (n.ver == ver)
                return n;
        }
        auto node = new DepNode(this, ver);
        nodes ~= node;
        return node;
    }

    /// Get existing node that match with [ver], or null
    package DepNode getNode(Semver ver) @safe
    {
        foreach (n; nodes)
        {
            if (n.ver == ver)
                return n;
        }
        return null;
    }

    Semver[] consideredVersions() const @safe
    {
        import std.algorithm : map;
        import std.array : array;

        return nodes.map!(n => cast(Semver) n.ver).array;
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

    /// The languages of this node and all dependencies
    /// This is generally fetched after resolution
    Lang[] langs;

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
        auto edge = new DepEdge;

        edge.up = up;
        edge.down = down;
        edge.spec = spec;

        up.downEdges ~= edge;
        down.upEdges ~= edge;

        return edge;
    }

    bool onResolvedPath() const @safe
    {
        return up.isResolved && down.resolvedNode !is null;
    }
}

/// Prepare a dependency DAG for the given recipe and profile.
DepDAG prepareDepDAG(Recipe recipe, Profile profile, CacheRepo cacheRepo, Heuristics heuristics) @system
{
    import std.algorithm : canFind, filter, sort, uniq;
    import std.array : array;

    DepPack[string] packs;

    DepPack prepDepPack(Dependency dep)
    {
        auto av = cacheRepo.packAvailVersions(dep.name)
            .filter!(v => dep.spec.matchVersion(v)).array;

        DepPack pack;
        if (auto p = dep.name in packs)
            pack = *p;

        if (pack)
        {
            av ~= pack.allVersions;
        }
        else
        {
            pack = new DepPack(dep.name);
            packs[dep.name] = pack;
        }

        pack.allVersions = sort(av).uniq().array;
        return pack;
    }

    DepNode[] visited;
    DepPack root = new DepPack(recipe.name);
    root.allVersions = [recipe.ver];

    void doPackVersion(DepPack pack, Semver ver)
    {
        auto node = pack.getOrCreateNode(ver);
        if (visited.canFind(node))
            return;

        visited ~= node;

        auto rec = pack is root ? recipe : cacheRepo.packRecipe(pack.name, ver);
        auto deps = rec.dependencies(profile);
        foreach (dep; deps)
        {
            auto dp = prepDepPack(dep);
            DepEdge.create(node, dp, dep.spec);

            const dv = chooseVersion(heuristics, cacheRepo, dp.name, dp.allVersions);
            doPackVersion(dp, dv);
        }
    }

    doPackVersion(root, recipe.ver);

    return DepDAG(root, heuristics);
}

/// Finalize filtering of incompatible versions in the DAG
/// This is done by successive up traversals until nothing changes
void checkDepDAGCompat(DepDAG dag) @trusted
{
    import std.algorithm : any, canFind, filter, remove;

    // compatibility check in bottom-up direction
    // returns whether some version was removed during traversal

    while (1)
    {
        bool diff;
        foreach (pack; dag.traverseBottomUp())
        {
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
        }

        if (!diff)
            break;
    }
}

/// Resolves a DAG such as each package has a resolved version
void resolveDepDAG(DepDAG dag, CacheRepo cacheRepo)
out(; dagIsResolved(dag))
{
    void resolveDeps(DepPack pack)
    in(pack.resolvedNode)
    {
        foreach (e; pack.resolvedNode.downEdges)
        {
            if (e.down.resolvedNode)
                continue;

            const resolved = chooseVersion(dag.heuristics, cacheRepo,
                    e.down.name, e.down.consideredVersions);

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

    dag.root.resolvedNode = dag.root.nodes[0];
    resolveDeps(dag.root);
}

/// Check whether a DAG is fully resolved
bool dagIsResolved(DepDAG dag) @safe
{
    import std.algorithm : all;

    return dag.traverseTopDown(Yes.root).all!((DepPack p) {
        return p.resolvedNode !is null;
    });
}

/// Collect all resolved nodes into a dictionary
/// Params
///     root = the root package of the DAG
/// Returns: A dictionary of all resolved nodes. Key is the package name.
DepNode[string] dagCollectResolved(DepDAG dag) @safe
{
    import std.algorithm : each;

    DepNode[string] res;

    dag.traverseTopDownResolved(Yes.root).each!(n => res[n.pack.name] = n);

    return res;
}

/// Fetch languages for each resolved node
/// This is used to compute the right profile to build
/// The dependency tree.
/// Each node is associated with its language + the cumulated
/// languages of its dependencies
void dagFetchLanguages(DepDAG dag, Recipe rootRecipe, CacheRepo cacheRepo) @safe
in(dagIsResolved(dag))
in(dag.root.name == rootRecipe.name)
in(dag.root.resolvedNode.ver == rootRecipe.ver)
{
    import std.algorithm : sort, uniq;
    import std.array : array;

    // Bottom-up traversal with collection of all languages along the way
    // It is possible to traverse several times the same package in case
    // of diamond dependency configuration. In this case, we have to cumulate the languages
    // from all passes

    void traverse(DepPack pack, Lang[] fromDeps) @safe
    {
        if (!pack.resolvedNode)
            return;

        const recipe = pack is dag.root ? rootRecipe
            : cacheRepo.packRecipe(pack.name, pack.resolvedNode.ver);

        // resolvedNodes may have been previously traversed, we add the previously found languages
        auto all = fromDeps ~ recipe.langs ~ pack.resolvedNode.langs;
        sort(all);
        auto langs = uniq(all).array;
        pack.resolvedNode.langs = langs;

        foreach (e; pack.upEdges)
            traverse(e.up.pack, langs);

    }

    auto leaves = dag.collectLeaves();
    foreach (l; leaves)
        traverse(l, []);
}

/// Issue a GraphViz' Dot representation of a DAG
string dagToDot(DepDAG dag) @safe
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

        foreach (pack; dag.traverseTopDown(Yes.root))
        {
            const name = format("cluster_%s", packNum++);
            packGNames[pack.name] = name;

            const(Semver)[] allVersions = pack.allVersions;
            const(Semver)[] consideredVersions = pack.consideredVersions;

            block("subgraph " ~ name, {

                line("label = \"%s\";", pack.name);
                line("node [shape=box];");

                foreach (v; allVersions)
                {
                    const nid = nodeId(pack.name, v);
                    const ngn = format("ver_%s", nodeNum++);
                    nodeGNames[nid] = ngn;

                    const considered = consideredVersions.find(v).length > 0;
                    string style = "dashed";
                    string color = "";
                    if (pack.resolvedNode && pack.resolvedNode.ver == v)
                    {
                        style = `"filled,solid"`;
                        color = ", color=teal";
                    }
                    else if (considered)
                    {
                        style = `"filled,solid"`;
                    }

                    line(`%s [label="%s", style=%s%s];`, ngn, v, style, color);
                }
            });
            line("");

        }

        // write all edges

        foreach (pack; dag.traverseTopDown(Yes.root))
        {
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
                        ? e.down.resolvedNode.ver : e.down.consideredVersions[$ - 1];
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
        }
    });

    return w.data;
}

/// Write Graphviz' dot representation of a DAG to [filename]
void dagToDot(DepDAG dag, string filename) @safe
{
    import std.file : write;

    const dot = dagToDot(dag);
    write(filename, dot);
}

/// Write Graphviz' dot represtation of a DAG directly to a png file
/// Requires dot command line tool to be in the PATH
void dagToDotPng(DepDAG dag, string filename) @safe
{
    import std.process : pipeProcess, Redirect;

    const dot = dagToDot(dag);

    const cmd = ["dot", "-Tpng", "-o", filename];
    auto pipes = pipeProcess(cmd, Redirect.stdin);

    pipes.stdin.write(dot);
}

version (unittest)
{
    import test.profile : ensureDefaultProfile;
}

@("Test general graph utility")
unittest
{
    import std.algorithm : canFind, map;
    import std.array : array;

    auto cacheRepo = TestCacheRepo.withBase();
    auto profile = ensureDefaultProfile();

    const heuristics = Heuristics.pickHighest;

    auto dag = prepareDepDAG(packE.recipe("1.0.0"), profile, cacheRepo, heuristics);

    auto leaves = dag.collectLeaves();
    assert(leaves.length == 1);
    assert(leaves[0].name == "a");

    string[] names = dag.traverseTopDown(Yes.root).map!(p => p.name).array;
    assert(names.length == 5);
    assert(names[0] == "e");
    assert(names.canFind("a", "b", "c", "d", "e"));

    names = dag.traverseTopDown(No.root).map!(p => p.name).array;
    assert(names.length == 4);
    assert(names.canFind("a", "b", "c", "d"));

    names = dag.traverseBottomUp(Yes.root).map!(p => p.name).array;
    assert(names.length == 5);
    assert(names[0] == "a");
    assert(names.canFind("a", "b", "c", "d", "e"));

    names = dag.traverseBottomUp(No.root).map!(p => p.name).array;
    assert(names.length == 4);
    assert(names[0] == "a");
    assert(names.canFind("a", "b", "c", "d"));

    // checkDepDAGCompat(dag);
    resolveDepDAG(dag, cacheRepo);

    names = dag.traverseTopDownResolved(Yes.root).map!(n => n.pack.name).array;
    assert(names.length == 5);
    assert(names[0] == "e");
    assert(names.canFind("a", "b", "c", "d", "e"));

    names = dag.traverseBottomUpResolved(Yes.root).map!(n => n.pack.name).array;
    assert(names.length == 5);
    assert(names[0] == "a");
    assert(names.canFind("a", "b", "c", "d", "e"));
}

@("Test Heuristic.preferCached")
unittest
{
    import std.algorithm : each;

    auto cacheRepo = TestCacheRepo.withBase();
    auto profile = ensureDefaultProfile();

    const heuristics = Heuristics.preferCached;

    auto dag = prepareDepDAG(packE.recipe("1.0.0"), profile, cacheRepo, heuristics);
    // checkDepDAGCompat(dag);
    resolveDepDAG(dag, cacheRepo);

    Semver[string] resolvedVersions;
    dag.traverseTopDownResolved(Yes.root).each!(n => resolvedVersions[n.pack.name] = n.ver);

    assert(resolvedVersions["a"] == "1.1.0");
    assert(resolvedVersions["b"] == "0.0.1");
    assert(resolvedVersions["c"] == "2.0.0");
    assert(resolvedVersions["d"] == "1.1.0");
    assert(resolvedVersions["e"] == "1.0.0");
}

@("Test Heuristic.pickHighest")
unittest
{
    import std.algorithm : each;

    auto cacheRepo = TestCacheRepo.withBase();
    auto profile = ensureDefaultProfile();

    const heuristics = Heuristics.pickHighest;

    auto dag = prepareDepDAG(packE.recipe("1.0.0"), profile, cacheRepo, heuristics);
    // checkDepDAGCompat(dag);
    resolveDepDAG(dag, cacheRepo);

    Semver[string] resolvedVersions;
    dag.traverseTopDownResolved(Yes.root).each!(n => resolvedVersions[n.pack.name] = n.ver);

    assert(resolvedVersions["a"] == "2.0.0");
    assert(resolvedVersions["b"] == "0.0.2");
    assert(resolvedVersions["c"] == "2.0.0");
    assert(resolvedVersions["d"] == "1.1.0");
    assert(resolvedVersions["e"] == "1.0.0");
}

@("Test dagFetchLanguages")
unittest
{
    auto cacheRepo = TestCacheRepo.withBase();
    auto profile = ensureDefaultProfile();

    const heuristics = Heuristics.pickHighest;

    auto recipe = packE.recipe("1.0.0");
    auto dag = prepareDepDAG(recipe, profile, cacheRepo, heuristics);

    checkDepDAGCompat(dag);
    resolveDepDAG(dag, cacheRepo);
    dagFetchLanguages(dag, recipe, cacheRepo);

    auto nodes = dagCollectResolved(dag);

    assert(nodes["a"].langs == [Lang.c]);
    assert(nodes["b"].langs == [Lang.d, Lang.c]);
    assert(nodes["c"].langs == [Lang.cpp, Lang.c]);
    assert(nodes["d"].langs == [Lang.d, Lang.cpp, Lang.c]);
    assert(nodes["e"].langs == [Lang.d, Lang.cpp, Lang.c]);
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

DepPack[] getMoreDown(DepPack pack)
{
    DepPack[] downs;
    foreach (n; pack.nodes)
    {
        foreach (e; n.downEdges)
        {
            downs ~= e.down;
        }
    }
    return downs;
}

DepPack[] getMoreUp(DepPack pack)
{
    import std.algorithm : map;
    import std.array : array;

    return pack.upEdges.map!(e => e.up.pack).array;
}

alias DepthFirstTopDownRange = DepthFirstRange!getMoreDown;
alias DepthFirstBottomUpRange = DepthFirstRange!getMoreUp;

struct DepthFirstRange(alias getMore)
{
    static struct Stage
    {
        DepPack[] packs;
        size_t ind;
    }

    Stage[] stack;
    DepPack[] visited;

    this(DepPack[] starter) @safe
    {
        stack = [Stage(starter, 0)];
    }

    this(Stage[] stack, DepPack[] visited) @safe
    {
        this.stack = stack;
        this.visited = visited;
    }

    @property bool empty() @safe
    {
        return stack.length == 0;
    }

    @property DepPack front() @safe
    {
        auto stage = stack[$ - 1];
        return stage.packs[stage.ind];
    }

    void popFront() @trusted
    {
        import std.algorithm : canFind;

        auto stage = stack[$ - 1];
        auto pack = stage.packs[stage.ind];

        visited ~= pack;

        while (1)
        {
            popFrontImpl(pack);
            if (!empty)
            {
                pack = front;
                if (visited.canFind(pack))
                    continue;
            }
            break;
        }
    }

    void popFrontImpl(DepPack frontPack)
    {
        // getting more on this way if possible
        DepPack[] more = getMore(frontPack);
        if (more.length)
        {
            stack ~= Stage(more, 0);
        }
        else
        {
            // otherwise going to sibling
            stack[$ - 1].ind += 1;
            // unstack while sibling are invalid
            while (stack[$ - 1].ind == stack[$ - 1].packs.length)
            {
                stack = stack[0 .. $ - 1];
                if (!stack.length)
                    return;
                else
                    stack[$ - 1].ind += 1;
            }
        }
    }

    @property DepthFirstRange!(getMore) save() @safe
    {
        return DepthFirstRange!(getMore)(stack.dup, visited.dup);
    }
}

package:

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
        Lang[] langs;

        Recipe recipe(string ver)
        {
            foreach (n; nodes)
            {
                if (n.ver == ver)
                {
                    return Recipe.mock(name, Semver(ver), n.deps, langs, "1");
                }
            }
            assert(false, "wrong version");
        }
    }

    TestPackage[] buildTestPackBase()
    {
        auto a = TestPackage("a", [
                TestPackVersion("1.0.0", [], true),
                TestPackVersion("1.1.0", [], true), TestPackVersion("1.1.1"),
                TestPackVersion("2.0.0"),
                ], [Lang.c]);

        auto b = TestPackage("b", [
                TestPackVersion("0.0.1", [
                        Dependency("a", VersionSpec(">=1.0.0 <2.0.0"))
                    ], true),
                TestPackVersion("0.0.2", [
                        Dependency("a", VersionSpec(">=1.1.0"))
                    ]),
                ], [Lang.d]);

        auto c = TestPackage("c", [
                TestPackVersion("1.0.0", [], true),
                TestPackVersion("2.0.0", [
                        Dependency("a", VersionSpec(">=1.1.0"))
                    ]),
                ], [Lang.cpp]);
        auto d = TestPackage("d", [
                TestPackVersion("1.0.0", [Dependency("c", VersionSpec("1.0.0"))], true),
                TestPackVersion("1.1.0", [Dependency("c", VersionSpec("2.0.0"))]),
                ], [Lang.d]);
        return [a, b, c, d];
    }

    TestPackage packE = TestPackage("e", [
            TestPackVersion("1.0.0", [
                    Dependency("b", VersionSpec(">=0.0.1")),
                    Dependency("d", VersionSpec(">=1.1.0")),
                ])
            ], [Lang.d]);

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

        static TestCacheRepo withBase()
        {
            return new TestCacheRepo(buildTestPackBase());
        }

        /// Get the dependencies of a package in its specified version
        Recipe packRecipe(string packname, Semver ver, string revision) @safe
        {
            import std.algorithm : find;
            import std.exception : enforce;
            import std.range : front;

            TestPackage p = packs[packname];
            TestPackVersion pv = p.nodes.find!(pv => pv.ver == ver).front;
            const rev = revision ? revision : "1";
            return Recipe.mock(packname, ver, pv.deps, p.langs, rev);
        }

        /// Get the available versions of a package
        Semver[] packAvailVersions(string packname) @safe
        {
            import std.algorithm : map;
            import std.array : array;

            return packs[packname].nodes.map!(pv => Semver(pv.ver)).array;
        }

        /// Check whether a package version is in local cache or not
        bool packIsCached(string packname, Semver ver, string revision) @safe
        {
            import std.algorithm : find;
            import std.range : front;

            return packs[packname].nodes.find!(pv => pv.ver == ver).front.cached;
        }
    }
}
