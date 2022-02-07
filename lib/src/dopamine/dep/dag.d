/// Dependency Directed Acyclic Graph
///
/// This a kind of hybrid graph with the following abstractions:
/// - [DepDAG]: main structure representing the complete graph and providing algorithms.
/// - [DagPack]: correspond to a package and gathers several versions
/// - [DagNode]: correspond to a package version, that express dependencies towards other packages
/// - [DagEdge]: correspond to a dependency specification.
///
/// Edges start from a [DagNode] and points towards a [DagPack] and hold a [VersionSpec] that
/// is used during resolution to select the resolved [DagNode] within pointed [DagPack]
///
/// The directions up and down used in this module refer to the following
/// - The DAG root is at the top. This is the package for which dependencies are resolved
/// - The DAG leaves are at the bottom. These are the dependencies that do not have dependencies themselves.
///
/// The strategy of resolution is dictated by the [Heuristics] struct.
module dopamine.dep.dag;

import dopamine.dep.service;
import dopamine.dep.spec;
import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;

/// Heuristics to help choosing a package version in a set of compatible versions.
/// By default, we always prefer to use what is available locally and allow to use
/// packages installed in the user system.
struct Heuristics
{
    /// Heuristics mode to define if we prefer to re-use what is available locally
    /// or if we always want the latest available version of a dependency
    enum Mode
    {
        /// Will pick the highest compatible version that is on the system,
        /// and revert to cache then network if none is found.
        /// The advantage of system dependencies is that their sub-dependencies
        /// are already installed, so the resolution do not go further.
        preferSystem,
        /// Will pick the highest compatible version that is cached,
        /// and revert to system (if allowed) then network if none is found.
        preferCache,
        /// Local refer to either user system package, or to the local cache.
        /// It means that no difference will be made between a system dependency
        /// and a cached recipe. If the highest local compatible version is available both
        /// from system and from cache, cache is preferred.
        preferLocal,
        /// Will always pick the highest compatible version regardless if it is local or not
        /// If the highest version is available both locally and network,
        /// The order of preference is cache, then system (if allowed), then network.
        pickHighest,
    }

    /// Enum to describe the strategy in regards to dependency available
    /// in the user system.
    enum System
    {
        /// Allow to use local system dependencies
        allow,
        /// Disallow to use local system dependencies
        disallow,
        /// The allowed local system dependencies are listed in
        /// [systemList]
        allowedList,
        /// The allowed local system dependencies are *not* listed in
        /// [systemList]
        disallowedList,
    }

    Mode mode;
    System system;
    string[] systemList;

    /// Check whether using system dependency is allowed for [packname]
    bool allowSystemFor(string packname) const
    {
        import std.algorithm : canFind;

        final switch (system)
        {
        case System.allow:
            return true;
        case System.disallow:
            return false;
        case System.allowedList:
            return systemList.canFind(packname);
        case System.disallowedList:
            return !systemList.canFind(packname);
        }
    }

    /// Check whether the provided [AvailVersion] of [packname] is compatible
    /// with defined heuristics.
    bool allow(string packname, AvailVersion aver) const
    {
        if (aver.location != DepLocation.system)
        {
            return true;
        }
        return allowSystemFor(packname);
    }

    /// Choose a compatible version according defined heuristics.
    /// [compatibleVersions] have already been checked as compatible for the target.
    /// [compatibleVersions] MUST be sorted.
    AvailVersion chooseVersion(const(AvailVersion)[] compatibleVersions) const
    {
        import std.algorithm : map, maxIndex;
        import std.array : array;

        // no choice = no brainer
        if (compatibleVersions.length == 1)
            return compatibleVersions[0];

        static struct ScoredVersion
        {
            AvailVersion aver;
            int score;
        }

        const int highScore = cast(int)(10 * compatibleVersions.length);
        const int midScore = highScore / 2;
        const int lowScore = 1;

        int systemScore;
        int cacheScore;
        int verBumpScore;

        final switch (mode)
        {
        case Mode.preferSystem:
            systemScore = highScore;
            cacheScore = midScore;
            verBumpScore = lowScore;
            break;

        case Mode.preferCache:
            systemScore = midScore;
            cacheScore = highScore;
            verBumpScore = lowScore;
            break;

        case Mode.preferLocal:
            systemScore = highScore;
            cacheScore = highScore + 1; // cache is prefered over system
            // the following +1 avoids tie if we have system one version above the last cache
            verBumpScore = lowScore + 1;
            break;

        case Mode.pickHighest:
            systemScore = lowScore;
            cacheScore = midScore;
            verBumpScore = highScore;
            break;
        }

        auto sver = compatibleVersions
            .map!(aver => ScoredVersion(aver, 0))
            .array;

        Semver currentVer = compatibleVersions[0].ver;
        int verCount = 1;
        foreach (ref sv; sver)
        {
            assert(sv.aver.ver >= currentVer, "compatibleVersions is not sorted!");
            if (sv.aver.ver > currentVer)
            {
                verCount += 1;
                currentVer = sv.aver.ver;
            }

            final switch (sv.aver.location)
            {
            case DepLocation.system:
                sv.score = systemScore;
                break;
            case DepLocation.cache:
                sv.score = cacheScore;
                break;
            case DepLocation.network:
                break;
            }

            sv.score += verCount * verBumpScore;
        }
        import std.stdio;

        const maxI = sver.map!(sv => sv.score).maxIndex;
        return compatibleVersions[maxI];
    }
}

@("Heuristics.chooseVersion")
unittest
{
    // semantics of versions do not really matter here, only the order
    const compatibleVersions1 = [
        AvailVersion(Semver("1.0.0"), DepLocation.system),
        AvailVersion(Semver("1.0.0"), DepLocation.cache),
        AvailVersion(Semver("1.0.0"), DepLocation.network),
        AvailVersion(Semver("2.0.0"), DepLocation.system),
        AvailVersion(Semver("2.0.0"), DepLocation.cache),
        AvailVersion(Semver("2.0.0"), DepLocation.network),
        AvailVersion(Semver("3.0.0"), DepLocation.system),
        AvailVersion(Semver("3.0.0"), DepLocation.cache),
        AvailVersion(Semver("3.0.0"), DepLocation.network),
    ];
    const compatibleVersions2 = [
        AvailVersion(Semver("1.0.0"), DepLocation.cache),
        AvailVersion(Semver("2.0.0"), DepLocation.system),
        AvailVersion(Semver("3.0.0"), DepLocation.network),
    ];
    const compatibleVersions3 = [
        AvailVersion(Semver("1.0.0"), DepLocation.system),
        AvailVersion(Semver("2.0.0"), DepLocation.cache),
        AvailVersion(Semver("3.0.0"), DepLocation.network),
    ];

    const heuristicsSys = Heuristics(Heuristics.Mode.preferSystem);
    const heuristicsCache = Heuristics(Heuristics.Mode.preferCache);
    const heuristicsLocal = Heuristics(Heuristics.Mode.preferLocal);
    const heuristicsHighest = Heuristics(Heuristics.Mode.pickHighest);

    assert(heuristicsSys.chooseVersion(compatibleVersions1) ==
            AvailVersion(Semver("3.0.0"), DepLocation.system));
    assert(heuristicsSys.chooseVersion(compatibleVersions2) ==
            AvailVersion(Semver("2.0.0"), DepLocation.system));
    assert(heuristicsSys.chooseVersion(compatibleVersions3) ==
            AvailVersion(Semver("1.0.0"), DepLocation.system));

    assert(heuristicsCache.chooseVersion(compatibleVersions1) ==
            AvailVersion(Semver("3.0.0"), DepLocation.cache));
    assert(heuristicsCache.chooseVersion(compatibleVersions2) ==
            AvailVersion(Semver("1.0.0"), DepLocation.cache));
    assert(heuristicsCache.chooseVersion(compatibleVersions3) ==
            AvailVersion(Semver("2.0.0"), DepLocation.cache));

    assert(heuristicsLocal.chooseVersion(compatibleVersions1) ==
            AvailVersion(Semver("3.0.0"), DepLocation.cache));
    assert(heuristicsLocal.chooseVersion(compatibleVersions2) ==
            AvailVersion(Semver("2.0.0"), DepLocation.system));
    assert(heuristicsLocal.chooseVersion(compatibleVersions3) ==
            AvailVersion(Semver("2.0.0"), DepLocation.cache));

    assert(heuristicsHighest.chooseVersion(compatibleVersions1) ==
            AvailVersion(
                Semver("3.0.0"), DepLocation.cache));
    assert(heuristicsHighest.chooseVersion(compatibleVersions2) ==
            AvailVersion(
                Semver("3.0.0"), DepLocation.network));
    assert(heuristicsHighest.chooseVersion(compatibleVersions3) ==
            AvailVersion(
                Semver("3.0.0"), DepLocation.network));
}

/// A Directed Acyclic Graph for depedency resolution.
/// [DepDAG] is constructed with the [prepare] static method
/// and graph's internals are accessed through the root member,
/// and the provided algorithms.
struct DepDAG
{
    import std.typecons : Flag, No;

    private DagPack _root;
    private Heuristics _heuristics;

    /// Prepare a Dependency DAG for the given parameters.
    /// The recipe is the one of the root package.
    /// The profile is involved because packages may declare different dependencies
    /// for different profiles.
    /// This function returns a non resolved graph, in which each node can still
    /// have a choice of several dependencies versions to choose from, some of
    /// which can be incompatible (although a first pass of choice is already made).
    /// Incompatibilites can exist mainly in the case of different sub-dependencies
    /// having a common dependency, with different version specs (aka diamond graph layout).
    static DepDAG prepare(Recipe recipe, Profile profile, DepService service,
        Heuristics heuristics = Heuristics.init) @system
    {
        import std.algorithm : canFind, filter, sort, uniq;
        import std.array : array;

        DagPack[string] packs;

        DagPack prepareDagPack(DepSpec dep)
        {
            auto avs = service.packAvailVersions(dep.name)
                .filter!(av => dep.spec.matchVersion(av.ver))
                .filter!(av => heuristics.allow(dep.name, av))
                .array;

            DagPack pack;
            if (auto p = dep.name in packs)
                pack = *p;

            if (pack)
            {
                avs ~= pack.allVersions;
            }
            else
            {
                pack = new DagPack(dep.name);
                packs[dep.name] = pack;
            }

            pack.allVersions = sort(avs).uniq().array;
            return pack;
        }

        auto root = new DagPack(recipe.name);
        const aver = AvailVersion(recipe.ver, DepLocation.cache);
        root.allVersions = [aver];

        DagNode[] visited;

        void doPackVersion(Recipe rec, DagPack pack, AvailVersion aver)
        {
            auto node = pack.getOrCreateNode(aver);
            if (visited.canFind(node))
            {
                return;
            }

            visited ~= node;

            const(DepSpec)[] deps;
            if (aver.location != DepLocation.system)
            {
                deps = rec.dependencies(profile);
                if (pack !is root)
                {
                    node.revision = rec.revision;
                }
            }

            foreach (dep; deps)
            {
                auto dp = prepareDagPack(dep);
                DagEdge.create(node, dp, dep.spec);

                const dv = heuristics.chooseVersion(dp.allVersions);
                doPackVersion(service.packRecipe(dep.name, dv), dp, dv);
            }
        }

        doPackVersion(recipe, root, aver);

        return DepDAG(root);
    }

    /// 2nd phase of filtering to eliminate all incompatible versions in the DAG.
    void checkCompat() @trusted
    {
        import std.algorithm : any, canFind, filter, remove;

        // compatibility check in bottom-up direction
        // returns whether some version was removed during traversal

        auto leaves = collectLeaves();

        while (1)
        {
            bool diff;
            foreach (pack; traverseBottomUpLeaves(leaves, No.root))
            {
                // Remove nodes of pack for which at least one up package is found
                // without compatibility with it
                DagPack[] ups;
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
                        pack.removeNode(n.aver);
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

    /// Final phase of to attribute a resolved version to each package
    void resolve()
    {
        void resolveDeps(DagPack pack)
        in (pack.resolvedNode)
        {
            foreach (e; pack.resolvedNode.downEdges)
            {
                if (e.down.resolvedNode)
                    continue;

                const resolved = _heuristics.chooseVersion(e.down.consideredVersions);

                foreach (n; e.down.nodes)
                {
                    if (n.aver == resolved)
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

    /// Check whether this DAG was prepared
    bool opCast(T : bool)() const @safe
    {
        return _root !is null;
    }

    /// The root node of the graph
    @property inout(DagPack) root() inout @safe
    {
        return _root;
    }

    /// The heuristics used to resolve this graph
    @property inout(Heuristics) heuristics() inout @safe
    {
        return _heuristics;
    }

    /// Check whether the graph is resolved.
    // FIXME makes this const by allowing const traversals
    @property bool resolved() @safe
    {
        import std.algorithm : all;
        import std.typecons : Yes;

        return traverseTopDown(Yes.root).all!((DagPack p) {
            return p.resolvedNode !is null;
        });
    }

    /// Get the languages involved in the DAG
    @property Lang[] allLangs() @safe
    {
        // languages are gathered at the root dag, so no need to go further down.
        if (root && root.resolvedNode)
            return root.resolvedNode.langs;
        return [];
    }

    /// Return a generic range of DagPack that will traverse the whole graph
    /// from top to bottom
    auto traverseTopDown(Flag!"root" traverseRoot = No.root) @safe
    {
        auto res = DepthFirstTopDownRange([root]);

        if (!traverseRoot)
            res.popFront();

        return res;
    }

    /// Return a generic range of DagPack that will traverse the whole graph
    /// from bottom to top
    auto traverseBottomUp(Flag!"root" traverseRoot = No.root) @safe
    {
        auto leaves = collectLeaves();
        return traverseBottomUpLeaves(leaves, traverseRoot);
    }

    private auto traverseBottomUpLeaves(DagPack[] leaves, Flag!"root" traverseRoot) @safe
    {
        if (!traverseRoot && leaves.length == 1 && leaves[0] is root)
        {
            return DepthFirstBottomUpRange([]);
        }

        auto res = DepthFirstBottomUpRange(leaves);

        if (!traverseRoot)
            res.visited ~= root;

        return res;
    }

    /// Return a generic range of DagNode that will traverse the whole graph
    /// from top to bottom, through the resolution path.
    auto traverseTopDownResolved(Flag!"root" traverseRoot = No.root) @safe
    {
        import std.algorithm : filter, map;

        return traverseTopDown(traverseRoot).filter!(p => (p.resolvedNode !is null))
            .map!(p => p.resolvedNode);
    }

    /// Return a generic range of DagNode that will traverse the whole graph
    /// from bottom to top, through the resolution path.
    auto traverseBottomUpResolved(Flag!"root" traverseRoot = No.root) @safe
    {
        import std.algorithm : filter, map;

        return traverseBottomUp(traverseRoot).filter!(p => (p.resolvedNode !is null))
            .map!(p => p.resolvedNode);
    }

    /// Collect all leaves from a graph, that is nodes without leaving edges
    inout(DagPack)[] collectLeaves() inout @safe
    {
        import std.algorithm : canFind;

        inout(DagPack)[] traversed;
        inout(DagPack)[] leaves;

        void collectLeaves(inout(DagPack) pack) @trusted
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

    /// Fetch languages for each resolved node.
    /// This is used to compute the right profile to build the dependency tree.
    /// Each node is associated with its language + the cumulated
    /// languages of its dependencies.
    void fetchLanguages(Recipe rootRecipe, DepService service) @system
    in (resolved)
    in (root.name == rootRecipe.name)
    in (root.resolvedNode.ver == rootRecipe.ver)
    {
        import std.algorithm : sort, uniq;
        import std.array : array;

        // Bottom-up traversal with collection of all languages along the way
        // It is possible to traverse several times the same package in case
        // of diamond dependency configuration. In this case, we have to cumulate the languages
        // from all passes

        void traverse(DagPack pack, Lang[] fromDeps)
        {
            if (!pack.resolvedNode)
                return;

            const rec = pack is root ?
                    rootRecipe :
                    service.packRecipe(pack.name, pack.resolvedNode.aver);

            // resolvedNode may have been previously traversed,
            // we add the previously found languages
            auto all = fromDeps ~ rec.langs ~ pack.resolvedNode.langs;
            sort(all);
            auto langs = uniq(all).array;
            pack.resolvedNode.langs = langs;

            foreach (e; pack.upEdges)
                traverse(e.up.pack, langs);
        }

        foreach (l; collectLeaves())
            traverse(l, []);
    }
}

/// Dependency DAG package : represent a package and gathers DAG nodes, each of which is a version of this package
class DagPack
{
    /// Name of the package
    string name;

    /// The available versions of the package that are compatible with the current state of the DAG.
    AvailVersion[] allVersions;

    /// The version nodes of the package that are considered for the resolution.
    /// This is a subset of allVersions
    DagNode[] nodes;

    /// The resolved version node
    DagNode resolvedNode;

    /// Edges towards packages that depends on this
    DagEdge[] upEdges;

    private this(string name) @safe
    {
        this.name = name;
    }

    /// Get node that match with [ver]
    /// Create one if doesn't exist
    package DagNode getOrCreateNode(const(AvailVersion) aver) @safe
    {
        foreach (n; nodes)
        {
            if (n.aver == aver)
                return n;
        }
        auto node = new DagNode(this, aver);
        nodes ~= node;
        return node;
    }

    /// Get existing node that match with [ver], or null
    package DagNode getNode(const(AvailVersion) aver) @safe
    {
        foreach (n; nodes)
        {
            if (n.aver == aver)
                return n;
        }
        return null;
    }

    const(AvailVersion)[] consideredVersions() const @safe
    {
        import std.algorithm : map;
        import std.array : array;

        return nodes.map!(n => n.aver).array;
    }

    /// Remove node matching with ver.
    /// Do not perform any cleanup in up/down edges
    private void removeNode(const(AvailVersion) aver) @safe
    {
        import std.algorithm : remove;

        nodes = nodes.remove!(n => n.aver == aver);
    }
}

/// Dependency DAG node: represent a package with a specific version
/// and a set of sub-dependencies.
class DagNode
{
    this(DagPack pack, AvailVersion aver) @safe
    {
        this.pack = pack;
        this.aver = aver;
    }

    /// The package owner of this version node
    DagPack pack;

    /// The package version and location of this node
    AvailVersion aver;

    /// The package version
    @property Semver ver() const @safe
    {
        return aver.ver;
    }

    /// The package location
    @property DepLocation location() const @safe
    {
        return aver.location;
    }

    /// The package revision
    string revision;

    /// The edges going to dependencies of this package
    DagEdge[] downEdges;

    /// The languages of this node and all dependencies
    /// This is generally fetched after resolution
    Lang[] langs;

    /// User data
    Object userData;

    bool isResolved() const @trusted
    {
        return pack.resolvedNode is this;
    }
}

/// Dependency DAG edge : represent a dependency and its associated version requirement
/// [up] has a dependency towards [down] with [spec]
class DagEdge
{
    DagNode up;
    DagPack down;
    VersionSpec spec;

    /// Create a dependency edge between a package version and another package
    static void create(DagNode up, DagPack down, VersionSpec spec) @safe
    {
        auto edge = new DagEdge;

        edge.up = up;
        edge.down = down;
        edge.spec = spec;

        up.downEdges ~= edge;
        down.upEdges ~= edge;
    }

    bool onResolvedPath() const @safe
    {
        return up.isResolved && down.resolvedNode !is null;
    }
}

private:

inout(DagPack)[] getMoreDown(inout(DagPack) pack)
{
    inout(DagPack)[] downs;
    foreach (n; pack.nodes)
    {
        foreach (e; n.downEdges)
        {
            downs ~= e.down;
        }
    }
    return downs;
}

// compilation fail if inout - to be investigated
DagPack[] getMoreUp(DagPack pack)
{
    import std.algorithm : map;
    import std.array : array;

    return pack.upEdges.map!(e => e.up.pack).array;
}

alias DepthFirstTopDownRange = DepthFirstRange!(getMoreDown);
alias DepthFirstBottomUpRange = DepthFirstRange!(getMoreUp);

struct DepthFirstRange(alias getMore)
{
    static struct Stage
    {
        DagPack[] packs;
        size_t ind;
    }

    Stage[] stack;
    DagPack[] visited;

    this(DagPack[] starter) @safe
    {
        if (starter.length)
            stack = [Stage(starter, 0)];
        else
            stack = [];
    }

    this(Stage[] stack, DagPack[] visited) @safe
    {
        this.stack = stack;
        this.visited = visited;
    }

    @property bool empty() @safe
    {
        return stack.length == 0;
    }

    @property DagPack front() @safe
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

    void popFrontImpl(DagPack frontPack)
    {
        // getting more on this way if possible
        DagPack[] more = getMore(frontPack);
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

// dfmt off
version (unittest):

struct TestPackVersion
{
    string ver;
    DepSpec[] deps;
    DepLocation loc;

    @property AvailVersion aver() const
    {
        return AvailVersion(Semver(ver), loc);
    }
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
    auto a = TestPackage(
        "a",
        [
            TestPackVersion("1.0.0", [], DepLocation.cache),
            TestPackVersion("1.1.0", [], DepLocation.cache),
            TestPackVersion("1.1.0", [], DepLocation.system),
            TestPackVersion("1.1.1", [], DepLocation.network),
            TestPackVersion("2.0.0", [], DepLocation.network),
        ],
        [Lang.c]
    );

    auto b = TestPackage(
        "b",
        [
            TestPackVersion(
                "0.0.1",
                [
                    DepSpec("a", VersionSpec(">=1.0.0 <2.0.0"))
                ],
                DepLocation.cache
            ),
            TestPackVersion(
                "0.0.2",
                [
                    DepSpec("a", VersionSpec(">=1.1.0"))
                ],
                DepLocation.network
            ),
        ],
        [Lang.d]
    );

    auto c = TestPackage(
        "c",
        [
            TestPackVersion(
                "1.0.0",
                [],
                DepLocation.cache
            ),
            TestPackVersion(
                "2.0.0",
                [
                    DepSpec("a", VersionSpec(">=1.1.0"))
                ],
                DepLocation.network),
        ],
        [Lang.cpp]
    );
    auto d = TestPackage(
        "d", [
            TestPackVersion(
                "1.0.0",
                [
                    DepSpec("c", VersionSpec("1.0.0"))
                ],
                DepLocation.cache
            ),
            TestPackVersion(
                "1.1.0",
                [
                    DepSpec("c", VersionSpec("2.0.0"))
                ],
                DepLocation.network
            ),
        ],
        [Lang.d]
    );
    return [a, b, c, d];
}

TestPackage packE = TestPackage(
    "e",
    [
        TestPackVersion(
            "1.0.0",
            [
                DepSpec("b", VersionSpec(">=0.0.1")),
                DepSpec("d", VersionSpec(">=1.1.0")),
            ],
            DepLocation.network
        )
    ],
    [Lang.d]
);


/// A mock Dependency Service
final class TestDepService : DepService
{
    TestPackage[string] packs;

    this(TestPackage[] packs)
    {
        foreach (p; packs)
        {
            this.packs[p.name] = p;
        }
    }

    static DepService withBase()
    {
        return new TestDepService(buildTestPackBase());
    }

    override AvailVersion[] packAvailVersions(string packname) @trusted
    {
        import std.algorithm : map;
        import std.array : array;

        return packs[packname].nodes.map!(pv => pv.aver).array;
    }

    override Recipe packRecipe(string packname, const(AvailVersion) aver, string rev)
    {
        import std.algorithm : find;
        import std.range : front;

        TestPackage p = packs[packname];
        TestPackVersion pv = p.nodes.find!(pv => pv.aver == aver).front;
        const revision = rev ? rev : "1";
        return Recipe.mock(packname, aver.ver, pv.deps, p.langs, revision);
    }
}
