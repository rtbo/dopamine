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

    static @property Heuristics preferSystem()
    {
        return Heuristics.init;
    }

    static @property Heuristics preferCache()
    {
        return Heuristics(Mode.preferCache);
    }

    static @property Heuristics preferLocal()
    {
        return Heuristics(Mode.preferLocal);
    }

    static @property Heuristics pickHighest()
    {
        return Heuristics(Mode.pickHighest);
    }

    Heuristics withSystemAllowed() const
    {
        return Heuristics(mode, System.allow);
    }

    Heuristics withSystemDisallowed() const
    {
        return Heuristics(mode, System.disallow);
    }

    Heuristics withSystemAllowedList(string[] allowedSystemList) const
    {
        return Heuristics(mode, System.allowedList, allowedSystemList);
    }

    Heuristics withSystemDisallowedList(string[] disallowedSystemList) const
    {
        return Heuristics(mode, System.disallowedList, disallowedSystemList);
    }

    /// Check whether the provided [AvailVersion] of [packname] is compatible
    /// with defined heuristics.
    bool allow(string packname, AvailVersion aver) const
    {
        import std.algorithm : canFind;

        if (aver.location != DepLocation.system)
        {
            return true;
        }

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

    /// Choose a compatible version according defined heuristics.
    /// [compatibleVersions] have already been checked as compatible for the target.
    /// [compatibleVersions] MUST be sorted.
    AvailVersion chooseVersion(const(AvailVersion)[] compatibleVersions) const
    in (compatibleVersions.length > 0)
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

        const maxI = sver.map!(sv => sv.score).maxIndex;
        return compatibleVersions[maxI];
    }
}

@("Heuristics.chooseVersion")
unittest
{
    // dfmt off
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
            AvailVersion(Semver("3.0.0"), DepLocation.cache));
    assert(heuristicsHighest.chooseVersion(compatibleVersions2) ==
            AvailVersion(Semver("3.0.0"), DepLocation.network));
    assert(heuristicsHighest.chooseVersion(compatibleVersions3) ==
            AvailVersion(Semver("3.0.0"), DepLocation.network));
    // dfmt on
}

/// A Directed Acyclic Graph for depedency resolution.
/// [DepDAG] is constructed with the [prepare] static method
/// and graph's internals are accessed through the root member,
/// and the provided algorithms.
struct DepDAG
{
    import std.typecons : Flag, No, Yes;

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
    ///
    /// Params:
    ///   recipe = Recipe from the root package
    ///   profile = Compilation profile. It is needed here because packages may declare
    ///             different depedencies for different profiles.
    ///   service = The dependency service to fetch available versions and recipes.
    ///   heuristics = The heuristics to select the dependencies.
    ///   preFilter = Whether or not to apply a first stage of compatibility and heuristics filtering.
    ///               Passing [No.preFilter] is mostly useful to get a view on the complete graph,
    ///               but otherwise less efficient and (in theory) without change on final resolution.
    ///               Default is [Yes.preFilter].
    ///
    /// Returns: a [DepDAG] ready for the next phase
    static DepDAG prepare(Recipe recipe, Profile profile, DepService service,
        const Heuristics heuristics = Heuristics.init, Flag!"preFilter" preFilter = Yes.preFilter) @system
    {
        import std.algorithm : canFind, filter, sort, uniq;
        import std.array : array;

        DagPack[string] packs;

        DagPack prepareDagPack(DepSpec dep)
        {
            auto allAvs = service.packAvailVersions(dep.name);
            auto avs = preFilter ?
                allAvs
                .filter!(av => dep.spec.matchVersion(av.ver))
                .filter!(av => heuristics.allow(dep.name, av))
                .array : allAvs;

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

            const(DepSpec)[] deps = rec.dependencies(profile);
            if (pack !is root)
            {
                node.revision = rec.revision;
            }

            foreach (dep; deps)
            {
                auto dp = prepareDagPack(dep);
                DagEdge.create(node, dp, dep.spec);

                const dvs = preFilter ? [
                    heuristics.chooseVersion(dp.allVersions)
                ] : dp.allVersions;

                foreach (dv; dvs)
                {
                    // stop recursion for system dependencies
                    if (dv.location == DepLocation.system)
                    {
                        // ensure node is created before stopping
                        auto dn = dp.getOrCreateNode(dv);
                        if (!visited.canFind(dn))
                        {
                            visited ~= dn;
                        }
                        continue;
                    }

                    doPackVersion(service.packRecipe(dep.name, dv), dp, dv);
                }
            }
        }

        doPackVersion(recipe, root, aver);

        return DepDAG(root);
    }

    /// 2nd phase of filtering to eliminate all incompatible versions in the DAG.
    /// Unless [preFilter] was disabled during the [prepare] phase, this algorithm will only handle
    /// some special cases, like diamond layout or such.
    ///
    /// Throws: UnresolvedDepException
    void checkCompat() @trusted
    {
        import std.algorithm : any, canFind, filter, remove;

        // dumb compatibility check in bottom-up direction
        // we simply loop until nothing more changes

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

                if (pack.nodes.length == 0)
                {
                    throw new UnresolvedDepException(pack, ups);
                }

            }

            if (!diff)
                break;
        }
    }

    /// Final phase of resolution to attribute a resolved version to each package
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
        rootRecipe : service.packRecipe(pack.name, pack.resolvedNode.aver);

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

    /// Collect all resolved nodes to a dictionary
    DagNode[string] collectResolved() @safe
    {
        import std.algorithm : each;

        DagNode[string] res;

        traverseTopDownResolved(Yes.root).each!(n => res[n.pack.name] = n);

        return res;
    }

    /// Collect all resolved nodes that are dependencies of the given [node]
    DagNode[string] collectDependencies(DagNode node) @safe
    {
        DagNode[string] res;

        void doNode(DagNode n) @safe
        {
            res[n.pack.name] = n;
            foreach (e; n.downEdges)
            {
                if (e.down.resolvedNode)
                {
                    doNode(e.down.resolvedNode);
                }
            }
        }

        foreach (e; node.downEdges)
        {
            if (e.down.resolvedNode)
            {
                doNode(e.down.resolvedNode);
            }
        }

        return res;
    }

    /// Issue a GraphViz' Dot representation of the graph
    // FIXME: make this const by allowing const traversals
    string toDot() @safe
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

        void block(string header, void delegate() dg) @trusted
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

        string nodeId(string packname, const(AvailVersion) aver) @safe
        {
            return format("%s-%s-%s", packname, aver.ver, aver.location);
        }

        string nodeGName(string packname, const(AvailVersion) aver) @safe
        {
            const id = nodeId(packname, aver);
            const res = nodeGNames[id];
            assert(res, "unprocessed version: " ~ id);
            return res;
        }

        block("digraph G", {
            line("");
            line("graph [compound=true ranksep=1];");
            line("");

            // write clusters / pack

            foreach (pack; traverseTopDown(Yes.root))
            {
                const name = format("cluster_%s", packNum++);
                packGNames[pack.name] = name;

                const(AvailVersion)[] allVersions = pack.allVersions;
                const(AvailVersion)[] consideredVersions = pack.consideredVersions;

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
                        if (pack.resolvedNode && pack.resolvedNode.aver == v)
                        {
                            style = `"filled,solid"`;
                            color = ", color=teal";
                        }
                        else if (considered)
                        {
                            style = `"filled,solid"`;
                        }

                        const label = pack == root ? v.ver.toString() : format("%s (%s)", v.ver, v
                        .location);
                        line(
                        `%s [label="%s", style=%s%s];`,
                        ngn, label, style, color
                        );
                    }
                });
                line("");

            }

            // write all edges

            foreach (pack; traverseTopDown(Yes.root))
            {
                foreach (n; pack.nodes)
                {
                    const ngn = nodeGName(pack.name, n.aver);
                    foreach (e; n.downEdges)
                    {
                        // if down pack has a resolved version, we point to it directly
                        // otherwise we point to subgraph (the pack).

                        // To point to a subgraph, we still must point to a particular node
                        // in the subgraph and specify lhead
                        // we pick the last highest version in an arbitrary way
                        // it makes the arrows point towards it, but stop at the subgraph border
                        // in case of non-resolvable graph (pack without node), we point to the first version

                        string[] props;
                        AvailVersion downNode;

                        if (e.down.resolvedNode)
                        {
                            downNode = e.down.resolvedNode.aver;
                        }
                        else if (e.down.nodes.length)
                        {
                            downNode = e.down.nodes[$ - 1].aver;
                        }
                        else if (e.down.allVersions.length)
                        {
                            props ~= "color=\"crimson\"";
                            downNode = e.down.allVersions[0];
                        }
                        else
                        {
                            continue;
                        }

                        const downNgn = nodeGName(e.down.name, downNode);

                        if (!e.onResolvedPath)
                        {
                            const downPgn = packGNames[e.down.name];
                            assert(ngn, "unprocessed package: " ~ ngn);
                            props ~= format("lhead=%s", downPgn);
                        }

                        props ~= format(`label=" %s  "`, e.spec);

                        // space around label to provide some margin
                        line(`%s -> %s [%s];`, ngn, downNgn, props.join(" "));
                    }
                }
            }
        });

        return w.data;
    }

    /// Issue a GraphViz' Dot representation of the graph to a dot file
    // FIXME: make this const by allowing const traversals
    void toDotFile(string filename) @safe
    {
        import std.file : write;

        const dot = toDot();
        write(filename, dot);
    }

    /// Write Graphviz' dot represtation directly to a png file
    /// Requires the `dot` command line tool to be in the PATH.
    void toDotPng(string filename) @safe
    {
        import std.process : pipeProcess, Redirect;

        const dot = toDot();

        const cmd = ["dot", "-Tpng", "-o", filename];
        auto pipes = pipeProcess(cmd, Redirect.stdin);

        pipes.stdin.write(dot);
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

    @property string name() const @safe
    {
        return pack.name;
    }

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

class UnresolvedDepException : Exception
{
    private this(DagPack pack, DagPack[] ups)
    {
        import std.algorithm : find;
        import std.array : Appender;
        import std.format : format;
        import std.range : front;

        Appender!string app;

        app.put(format(
            "Dependencies to \"%s\" could not be resolved to a single version:\n",
            pack.name
        ));

        foreach (up; ups)
        {
            const spec = pack.upEdges
                .find!(e => e.up.pack == up)
                .front
                .spec;

            app.put(format(" - %s depends on %s %s\n", up.name, pack.name, spec));
        }

        super(app.data);
    }
}

@("Test general graph utility")
unittest
{
    import std.algorithm : canFind, map;
    import std.array : array;
    import std.typecons : No, Yes;

    auto service = TestDepService.withBase();
    auto profile = mockProfileLinux();

    // preferSystem (default): b is a leave
    auto leaves = DepDAG.prepare(packE.recipe("1.0.0"), profile, service).collectLeaves();
    assert(leaves.length == 2);
    assert(leaves.map!(l => l.name).canFind("a", "b"));

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), profile, service, Heuristics.preferCache);

    // preferCache: only a is a leave
    leaves = dag.collectLeaves();
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

    // dag.toDotPng("prepared.png");

    dag.checkCompat();
    // dag.toDotPng("checked.png");
    dag.resolve();
    // dag.toDotPng("resolved.png");

    names = dag.traverseTopDownResolved(Yes.root).map!(n => n.pack.name).array;
    assert(names.length == 5);
    assert(names[0] == "e");
    assert(names.canFind("a", "b", "c", "d", "e"));

    names = dag.traverseBottomUpResolved(Yes.root).map!(n => n.pack.name).array;
    assert(names.length == 5);
    assert(names[0] == "a");
    assert(names.canFind("a", "b", "c", "d", "e"));
}

@("Test Heuristic.preferSystem")
unittest
{
    import std.algorithm : each;
    import std.typecons : Yes;

    auto service = TestDepService.withBase();
    auto profile = mockProfileLinux();

    const heuristics = Heuristics.preferSystem;

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), profile, service, heuristics);
    dag.checkCompat();
    dag.resolve();

    AvailVersion[string] resolvedVersions;
    dag.traverseTopDownResolved(Yes.root).each!(n => resolvedVersions[n.pack.name] = n.aver);

    assert(resolvedVersions["a"] == AvailVersion(Semver("1.1.0"), DepLocation.system));
    assert(resolvedVersions["b"] == AvailVersion(Semver("0.0.3"), DepLocation.system));
    assert(resolvedVersions["c"] == AvailVersion(Semver("2.0.0"), DepLocation.network));
    assert(resolvedVersions["d"] == AvailVersion(Semver("1.1.0"), DepLocation.network));
    assert(resolvedVersions["e"].ver == "1.0.0");
}

@("Test Heuristic.preferCached")
unittest
{
    import std.algorithm : each;
    import std.typecons : Yes;

    auto service = TestDepService.withBase();
    auto profile = mockProfileLinux();

    const heuristics = Heuristics.preferCache;

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), profile, service, heuristics);
    dag.checkCompat();
    dag.resolve();

    AvailVersion[string] resolvedVersions;
    dag.traverseTopDownResolved(Yes.root).each!(n => resolvedVersions[n.pack.name] = n.aver);

    assert(resolvedVersions["a"] == AvailVersion(Semver("1.1.0"), DepLocation.cache));
    assert(resolvedVersions["b"] == AvailVersion(Semver("0.0.1"), DepLocation.cache));
    assert(resolvedVersions["c"] == AvailVersion(Semver("2.0.0"), DepLocation.network));
    assert(resolvedVersions["d"] == AvailVersion(Semver("1.1.0"), DepLocation.network));
    assert(resolvedVersions["e"].ver == "1.0.0");
}

@("Test Heuristic.preferLocal")
unittest
{
    import std.algorithm : each;
    import std.typecons : Yes;

    auto service = TestDepService.withBase();
    auto profile = mockProfileLinux();

    const heuristics = Heuristics.preferLocal;

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), profile, service, heuristics);
    dag.checkCompat();
    dag.resolve();

    AvailVersion[string] resolvedVersions;
    dag.traverseTopDownResolved(Yes.root).each!(n => resolvedVersions[n.pack.name] = n.aver);

    assert(resolvedVersions["a"] == AvailVersion(Semver("1.1.0"), DepLocation.cache));
    assert(resolvedVersions["b"] == AvailVersion(Semver("0.0.3"), DepLocation.system));
    assert(resolvedVersions["c"] == AvailVersion(Semver("2.0.0"), DepLocation.network));
    assert(resolvedVersions["d"] == AvailVersion(Semver("1.1.0"), DepLocation.network));
    assert(resolvedVersions["e"].ver == "1.0.0");
}

@("Test Heuristic.pickHighest")
unittest
{
    import std.algorithm : each;
    import std.typecons : Yes;

    auto service = TestDepService.withBase();
    auto profile = mockProfileLinux();

    const heuristics = Heuristics.pickHighest;

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), profile, service, heuristics);
    dag.checkCompat();
    dag.resolve();

    AvailVersion[string] resolvedVersions;
    dag.traverseTopDownResolved(Yes.root).each!(n => resolvedVersions[n.pack.name] = n.aver);

    assert(resolvedVersions["a"] == AvailVersion(Semver("2.0.0"), DepLocation.network));
    assert(resolvedVersions["b"] == AvailVersion(Semver("0.0.3"), DepLocation.system));
    assert(resolvedVersions["c"] == AvailVersion(Semver("2.0.0"), DepLocation.network));
    assert(resolvedVersions["d"] == AvailVersion(Semver("1.1.0"), DepLocation.network));
    assert(resolvedVersions["e"].ver == "1.0.0");
}

@("Test that No.preFilter has no impact on resolution")
unittest
{
    import std.algorithm : each, map, sort;
    import std.array : array;
    import std.typecons : No, Yes;

    auto service = TestDepService.withBase();
    auto profile = mockProfileLinux();

    const heuristics = Heuristics.preferSystem;

    auto dag1 = DepDAG.prepare(packE.recipe("1.0.0"), profile, service, heuristics);
    dag1.checkCompat();
    dag1.resolve();

    auto dag2 = DepDAG.prepare(packE.recipe("1.0.0"), profile, service, heuristics, No.preFilter);
    dag2.checkCompat();
    dag2.resolve();

    static struct NodeData
    {
        string name;
        Semver ver;
        DepLocation loc;

        int opCmp(const ref NodeData rhs) const
        {
            if (name < rhs.name)
                return -1;
            if (name > rhs.name)
                return 1;
            if (ver < rhs.ver)
                return -1;
            if (ver > rhs.ver)
                return 1;
            if (loc < rhs.loc)
                return -1;
            if (loc > rhs.loc)
                return 1;
            return 0;
        }
    }

    NodeData[] mapNodeData(DagNode[] nodes)
    {
        auto data = nodes.map!(n => NodeData(n.name, n.ver, n.location)).array;
        sort(data);
        return data;
    }

    auto resolved1 = mapNodeData(dag1.collectResolved().values);
    auto resolved2 = mapNodeData(dag2.collectResolved().values);

    assert(resolved1 == resolved2);
}

@("traverse without deps")
unittest
{
    import std.array : array;
    import std.typecons : Yes;

    auto pack = TestPackage("a", [
            TestPackVersion("1.0.1", [], DepLocation.cache)
        ], [Lang.c]);
    auto service = new TestDepService([]);
    auto profile = mockProfileLinux();

    auto dag = DepDAG.prepare(pack.recipe("1.0.1"), profile, service);
    dag.resolve();

    auto arr = dag.traverseTopDownResolved().array;
    assert(arr.length == 0);
    arr = dag.traverseTopDownResolved(Yes.root).array;
    assert(arr.length == 1);
    arr = dag.traverseBottomUpResolved().array;
    assert(arr.length == 0);
    arr = dag.traverseBottomUpResolved(Yes.root).array;
    assert(arr.length == 1);
}

@("Test DepDAG.fetchLanguages")
unittest
{
    auto service = TestDepService.withBase();
    auto profile = mockProfileLinux();

    auto recipe = packE.recipe("1.0.0");
    auto dag = DepDAG.prepare(recipe, profile, service);

    dag.checkCompat();
    dag.resolve();
    dag.fetchLanguages(recipe, service);

    auto nodes = dag.collectResolved();

    assert(nodes["a"].langs == [Lang.c]);
    assert(nodes["b"].langs == [Lang.d]);
    assert(nodes["c"].langs == [Lang.cpp, Lang.c]);
    assert(nodes["d"].langs == [Lang.d, Lang.cpp, Lang.c]);
    assert(nodes["e"].langs == [Lang.d, Lang.cpp, Lang.c]);
}

@("Test not resolvable DAG")
unittest
{
    import std.exception : assertThrown;

    auto service = TestDepService.withNotResolvableBase();
    auto profile = mockProfileLinux();

    auto recipe = packNotResolvable.recipe("1.0.0");
    auto dag = DepDAG.prepare(recipe, profile, service);

    assertThrown!UnresolvedDepException(dag.checkCompat());
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
                [],
                DepLocation.network
            ),
            TestPackVersion(
                "0.0.3",
                [
                    DepSpec("a", VersionSpec(">=1.1.0"))
                ],
                DepLocation.system
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

TestPackage[] buildNotResolvable()
{
    auto a = TestPackage(
        "a",
        [
            TestPackVersion(
                "1.0.0",
                [],
                DepLocation.cache,
            ),
            TestPackVersion(
                "2.0.0",
                [],
                DepLocation.cache,
            ),
        ],
        [Lang.c],
    );

    // a DepDAG depending on both b and c cannot be resolved

    auto b = TestPackage(
        "b",
        [
            TestPackVersion(
                "1.0.0",
                [
                    DepSpec("a", VersionSpec("1.0.0")),
                ],
                DepLocation.cache,
            ),
        ],
        [Lang.c],
    );

    auto c = TestPackage(
        "c",
        [
            TestPackVersion(
                "1.0.0",
                [
                    DepSpec("a", VersionSpec("2.0.0")),
                ],
                DepLocation.cache,
            ),
        ],
        [Lang.c],
    );
    return [a, b, c];
}

TestPackage packNotResolvable = TestPackage(
    "not-resolvable",
    [
        TestPackVersion(
            "1.0.0",
            [
                DepSpec("b", VersionSpec("1.0.0")),
                DepSpec("c", VersionSpec("1.0.0")),
            ],
            DepLocation.cache,
        ),
    ],
    [Lang.c],
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

    static DepService withNotResolvableBase()
    {
        return new TestDepService(buildNotResolvable());
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
