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

import std.typecons : Nullable;

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

        if (!aver.location.isSystem)
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
    AvailVersion chooseVersion(const(AvailVersion)[] compatibleVersions) const @safe
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
    import std.json;
    import std.typecons : Flag, No, Yes;

    @disable this();

    package this(DagPack root, const Heuristics heuristics)
    {
        _root = root;
        _heuristics = heuristics;
    }

    package this(DagPack root, DepServices services, const Heuristics heuristics)
    {
        _root = root;
        _services = services;
        _heuristics = heuristics;
    }

    private DagPack _root;
    private DepServices _services;
    private const(Heuristics) _heuristics;

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
    ///   config = Build configuration. It is needed here because packages may declare
    ///            different depedencies for different configs.
    ///   service = The dependency service to fetch available versions and recipes.
    ///   heuristics = The heuristics to select the dependencies.
    ///   preFilter = Whether or not to apply a first stage of compatibility and heuristics filtering.
    ///               Passing [No.preFilter] is mostly useful to get a view on the complete graph,
    ///               but otherwise less efficient and (in theory) without change on final resolution.
    ///               Default is [Yes.preFilter].
    ///
    /// Returns: a [DepDAG] ready for the next phase
    static DepDAG prepare(
        RecipeDir rdir,
        const(BuildConfig) config,
        DepServices services,
        const Heuristics heuristics = Heuristics.init,
        Flag!"preFilter" preFilter = Yes.preFilter) @system
    in (rdir.recipe, "RecipeDir must have a recipe loaded")
    {
        import std.algorithm : canFind, filter;
        import std.array : array;

        static string packId(string name, bool dub) pure @safe
        {
            import std.digest.sha;
            import std.string : representation;

            auto dig = makeDigest!SHA1();
            dig.put(name.representation);
            dig.put(0);
            dig.put(dub ? 1 : 0);
            return toHexString(dig.finish())[].idup;
        }

        static struct RecipeInfo
        {
            string name;
            bool dub;
        }

        DagPack[string] packs;

        DagPack prepareDagPack(const(DepSpec) dep)
        {
            auto service = dep.dub ? services.dub : services.dop;

            const rootName = dep.name.pkgName;
            const rootId = packId(rootName, dep.dub);
            auto rootPack = packs.get(rootId, null);
            if (!rootPack)
            {
                rootPack = new DagPack(rootName, dep.dub);
                rootPack._versionsCached = service.packAvailVersions(dep.name);
                packs[rootId] = rootPack;
            }

            DagPack pack;
            if (rootName == dep.name)
            {
                pack = rootPack;
            }
            else
            {
                // sub module
                const id = packId(dep.name, dep.dub);
                pack = packs.get(id, null);
                if (!pack)
                {
                    pack = new DagPack(dep.name, dep.dub);
                    pack.rootPack = rootPack;
                    rootPack.modPacks ~= pack;
                    packs[id] = pack;
                }
            }

            auto allAvs = rootPack._versionsCached;

            auto avs = preFilter ?
                allAvs
                    .filter!(av => dep.spec.matchVersion(av.ver))
                    .filter!(av => heuristics.allow(dep.name, av))
                    .array : allAvs;

            pack.addAvailVersions(avs);
            pack.options ~= dep.options.dup;

            return pack;
        }

        auto root = DagPack.makeRoot(rdir.recipe);

        DagNode[] visited;

        void doPackVersion(RecipeInfo rinfo, DagPack pack, AvailVersion aver)
        {
            auto node = pack.getOrCreateNode(aver);

            if (visited.canFind(node))
                return;
            visited ~= node;

            const(DepSpec)[] deps;
            if (pack is root)
            {
                deps = rdir.recipe.dependencies(config);
            }
            else
            {
                auto service = rinfo.dub ? services.dub : services.dop;
                deps = service.packDependencies(config, rinfo.name, aver);
            }

            foreach (dep; deps)
            {
                auto service = dep.dub ? services.dub : services.dop;

                auto dp = prepareDagPack(dep);
                DagEdge.create(node, dp, dep.spec);

                foreach (dv; dp.allVersions)
                {
                    // stop recursion for system dependencies
                    if (dv.location.isSystem)
                    {
                        // ensure node is created before stopping
                        auto dn = dp.getOrCreateNode(dv);
                        if (!visited.canFind(dn))
                            visited ~= dn;

                        continue;
                    }

                    doPackVersion(RecipeInfo(dep.name, dep.dub), dp, dv);
                }
            }
        }

        const rootInfo = RecipeInfo(rdir.recipe.name, rdir.recipe.isDub);

        doPackVersion(rootInfo, root, root.allVersions[0]);

        return DepDAG(root, services, heuristics);
    }

    /// Final phase of resolution to eliminate incompatible versions and
    /// attribute a resolved version to each package.
    ///
    /// Throws:
    /// UnresolvedDepException if a dependency cannot be resolved to a single version.
    void resolve() @system
    {
        void resolveDeps(DagPack pack) @system
        in (pack.resolvedNode)
        {
            foreach (e; pack.resolvedNode.downEdges)
            {
                if (e.down.resolvedNode)
                    continue;

                auto service = e.down.dub ? _services.dub : _services.dop;

                // for submodule, assign the version resolved for the package
                if (e.down.rootPack && e.down.rootPack.resolvedNode)
                {
                    const resolved = e.down.rootPack.resolvedNode.aver;
                    auto rn = e.down.getNode(resolved);
                    assert(rn, "Version discrepancy between package and submodules");
                    string revision = e.down.rootPack.resolvedNode.revision;
                    if (!revision.length && !e.down.dub)
                    {
                        auto rdir = service.packRecipe(e.down.rootPack.name, rn.aver);
                        revision = rdir.recipe.revision;
                        e.down.rootPack.resolvedNode.revision = revision;
                    }
                    rn.revision = revision;
                    e.down.resolvedNode = rn;
                }
                else
                {
                    const resolved = _heuristics.chooseVersion(e.down.consideredVersions);
                    auto rn = e.down.getNode(resolved);
                    assert(rn);
                    if (!e.down.dub && !resolved.location.isSystem)
                    {
                        auto rdir = service.packRecipe(e.down.name, rn.aver);
                        rn.revision = rdir.recipe.revision;
                    }
                    e.down.resolvedNode = rn;
                }

                resolveDeps(e.down);
            }
        }

        checkCompat();

        root.resolvedNode = root.nodes[0];
        resolveDeps(root);

        cascadeOptions();
    }

    // 2nd phase of filtering to eliminate all incompatible versions in the DAG.
    // Unless [preFilter] was disabled during the [prepare] phase, this algorithm will only handle
    // some special cases, like diamond layout or such.
    //
    // Throws: UnresolvedDepException
    private void checkCompat() @trusted
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
                    auto n = pack.nodes[ni];
                    bool rem;

                    foreach (up; ups)
                    {
                        // check if `n` is compatible with at least one version of `up`
                        // (no dependency to `n` also mean compatible)

                        bool compat;

                        foreach (un; up.nodes)
                        {
                            auto downToPack = un.downEdges
                                .filter!(e => e.down is pack);

                            const nodep = downToPack.empty;
                            const comp = downToPack.any!(e => e.spec.matchVersion(n.ver));

                            if (nodep || comp)
                            {
                                compat = true;
                                break;
                            }
                        }

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
                            e.down.upEdges = e.down.upEdges.remove!(ue => ue is e);
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

    private void cascadeOptions() @safe
    {
        import dopamine.log : logWarningH;
        import std.algorithm : startsWith;
        import std.array : join;

        OptionSet remaining;
        string[] remainingConflicts;

        void doPack(DagPack pack) @safe
        {
            auto rn = pack.resolvedNode;

            // Initialize node options and conflicts with those
            // from previous node that are targetting it.
            // Used remaining options are cleaned up.
            const prefix = pack.name ~ "/";
            rn.options = remaining.forDependency(pack.name);
            remaining = remaining.notFor(pack.name);
            foreach (c; remainingConflicts)
            {
                if (c.startsWith(prefix))
                    rn.optionConflicts ~= c[prefix.length .. $];
            }

            foreach (opt; pack.options)
            {
                rn.options = rn.options.merge(rn.optionConflicts, opt.forRoot(), opt.forDependency(
                        pack.name));
                remaining = remaining.merge(remainingConflicts, opt.notFor(pack.name));
            }

            foreach (DagEdge e; rn.downEdges)
            {
                doPack(e.down);
            }
        }

        doPack(_root);

        if (remaining.length)
        {
            logWarningH(
                "Some options were defined but not used in the dependency graph:\n - ",
                remaining.keys.join("\n - ")
            );
        }
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
    @property const(Heuristics) heuristics() const @safe
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
        return DependencyDrivenDownNodeRange(root, traverseRoot);
    }

    /// Return a generic range of DagNode that will traverse the whole graph
    /// from bottom to top, through the resolution path.
    auto traverseBottomUpResolved(Flag!"root" traverseRoot = No.root) @safe
    {
        auto leaves = collectResolvedLeaves();
        return DependencyDrivenUpNodeRange(leaves, traverseRoot);
    }

    /// Collect all leaves from a graph, that is nodes without leaving edges
    inout(DagPack)[] collectLeaves() inout @safe
    {
        import std.algorithm : canFind;

        inout(DagPack)[] traversed;
        inout(DagPack)[] leaves;

        void traverse(inout(DagPack) pack) @trusted
        {
            if (traversed.canFind(pack))
                return;
            traversed ~= pack;

            bool isLeaf = true;
            foreach (n; pack.nodes)
            {
                foreach (e; n.downEdges)
                {
                    traverse(e.down);
                    isLeaf = false;
                }
            }
            if (isLeaf)
            {
                leaves ~= pack;
            }
        }

        traverse(root);

        return leaves;
    }

    /// Collect all resolved leaves from a graph, that is resolved nodes without leaving edges
    inout(DagPack)[] collectResolvedLeaves() inout @safe
    {
        import std.algorithm : canFind;
        import std.range : empty;

        inout(DagPack)[] traversed;
        inout(DagPack)[] leaves;

        void traverse(inout(DagPack) pack) @trusted
        {
            if (traversed.canFind(pack))
                return;
            traversed ~= pack;

            foreach (e; pack.resolvedNode.downEdges)
                traverse(e.down);

            if (pack.resolvedNode.downEdges.empty)
                leaves ~= pack;
        }

        traverse(root);

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

    JSONValue toJson(Flag!"emitAllVersions" emitAllVersions = Yes.emitAllVersions) @safe
    {
        import dopamine.dep.lock : dagToJson;

        return dagToJson(this, emitAllVersions);
    }

    static DepDAG fromJson(JSONValue json) @safe
    {
        import dopamine.dep.lock : jsonToDag;

        return jsonToDag(json);
    }

    /// Issue a GraphViz' Dot representation of the graph
    // FIXME: make this const by allowing const traversals
    string toDot(DotOptions options = DotOptions.includeCompat) @safe
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

        const printAll = (options & DotOptions.includeAll) == DotOptions.includeAll;
        const printCompat = (options & DotOptions.includeCompat) == DotOptions.includeCompat;

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
                        const resolved = pack.resolvedNode && pack.resolvedNode.aver == v;

                        if (!considered && !printAll)
                            continue;
                        if (!resolved && !printCompat)
                            continue;

                        string style = "dashed";
                        string color = "";

                        if (resolved)
                        {
                            style = `"filled,solid"`;
                            color = ", color=teal";
                        }
                        else if (considered)
                        {
                            style = `"filled,solid"`;
                        }

                        const label = pack == root
                        ? v.ver.toString() : format("%s (%s)", v.ver, v.location);
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
    void toDotFile(string filename, DotOptions options = DotOptions.includeCompat) @safe
    {
        import std.file : write;

        const dot = toDot(options);
        write(filename, dot);
    }

    /// Write Graphviz' dot represtation directly to a png file
    /// Requires the `dot` command line tool to be in the PATH.
    void toDotPng(string filename, DotOptions options = DotOptions.includeCompat) @safe
    {
        import std.process : pipeProcess, Redirect;

        const dot = toDot(options);

        const cmd = ["dot", "-Tpng", "-o", filename];
        auto pipes = pipeProcess(cmd, Redirect.stdin);

        pipes.stdin.write(dot);
    }
}

enum DotOptions
{
    /// Only show the resolved nodes
    resolvedOnly = 0,
    /// Include versions that are compatible, but not chosen as "resolved"
    includeCompat = 1,
    /// Include all versions, including those not compatible with dependency graph
    includeAll = 3,
}

/// Dependency DAG package : represent a package and gathers DAG nodes, each of which is a version of this package
final class DagPack
{
    // TODO: fix this module privacy

    private string _name;
    private bool _dub;
    package AvailVersion[] _allVersions; // versions compatible with current resolution level
    package AvailVersion[] _versionsCached; // all versions cached from service
    private DagNode _resolvedNode;

    private OptionSet[] options;

    // if this is a submodule package, have a reference to the root package
    private DagPack rootPack;
    // if this has submodule packages, their list is here
    private DagPack[] modPacks;

    /// The version nodes of the package that are considered for the resolution.
    /// This is a subset of allVersions
    DagNode[] nodes;

    /// Edges towards packages that depends on this
    DagEdge[] upEdges;

    package this(string name, bool dub) @trusted
    {
        _name = name;
        _dub = dub;
    }

    private void addAvailVersions(AvailVersion[] avs) @trusted
    {
        import std.algorithm : sort, uniq;
        import std.array : array;

        if (rootPack)
        {
            rootPack.addAvailVersions(avs);
        }
        else
        {
            _allVersions ~= avs;
            _allVersions = sort(_allVersions).uniq().array;
        }
    }

    package static DagPack makeRoot(const(Recipe) recipe)
    {
        auto root = new DagPack(recipe.name, recipe.isDub);
        root.addAvailVersions([AvailVersion(recipe.ver, DepLocation.cache)]);
        return root;
    }

    /// The name of the package
    @property PackageName name() const @safe
    {
        return PackageName(_name);
    }

    /// Whether this is a dub package
    @property bool dub() const @safe
    {
        return _dub;
    }

    @property bool isRoot() const @safe
    {
        return upEdges.length == 0;
    }

    /// The available versions of the package that are compatible with the current state of the DAG.
    @property const(AvailVersion)[] allVersions() const @safe
    {
        if (rootPack)
            return rootPack.allVersions;
        return _allVersions;
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

        // for submodules, create the same node for the same version
        // for each module in the super package.
        assert(!(rootPack && modPacks.length), "Can't be root and non-root at the same time");
        if (rootPack)
            rootPack.getOrCreateNode(aver);
        foreach (mp; modPacks)
            mp.getOrCreateNode(aver);

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

    /// The resolved version node
    @property inout(DagNode) resolvedNode() inout @safe
    {
        return _resolvedNode;
    }

    /// ditto
    package(dopamine.dep) @property void resolvedNode(DagNode node) @safe
    {
        assert(node.pack is this);

        _resolvedNode = node;
    }
}

/// Dependency DAG node: represent a package with a specific version
/// and a set of sub-dependencies.
final class DagNode
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

    /// The options for this node coming from the top of the graph.
    /// This field is populated only once the graph is resolved.
    OptionSet options;

    /// The options conflicts to be resolved for this node
    string[] optionConflicts;

    @property PackageName name() const @safe
    {
        return pack.name;
    }

    @property bool dub() const @safe
    {
        return pack.dub;
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

    /// Build info
    Nullable!DepBuildInfo buildInfo;

    /// Depth level of this node. (root is 0)
    @property int level() const
    {
        if (!pack.upEdges.length)
            return 0;

        int lev = int.max;
        foreach (up; pack.upEdges)
        {
            int ll = up.up.level + 1;
            if (ll < lev)
                lev = ll;
        }
        return lev;
    }

    bool isResolved() const @trusted
    {
        return pack.resolvedNode is this;
    }

    /// Collect all resolved nodes that are dependencies of this node
    DagNode[string] collectDependencies() @safe
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

        foreach (e; downEdges)
        {
            if (e.down.resolvedNode)
            {
                doNode(e.down.resolvedNode);
            }
        }

        return res;
    }
}

/// Dependency DAG edge : represent a dependency and its associated version requirement
/// [up] has a dependency towards [down] with [spec]
final class DagEdge
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
    private this(DagPack pack, DagPack[] ups, string file = __FILE__, size_t line = __LINE__)
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

        super(app.data, file, line);
    }
}

version (unittest)
{
    import unit_threaded.assertions;

    BuildConfig mockConfigLinux()
    {
        auto profile = mockProfileLinux();
        return BuildConfig(profile, [], OptionSet.init);
    }
}

@("Test general graph utility")
unittest
{
    import std.algorithm : canFind, map;
    import std.array : array;
    import std.typecons : No, Yes;

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    // preferSystem (default): b is a leave
    //auto leaves = DepDAG.prepare(packE.recipe("1.0.0"), config, services).collectLeaves();
    auto dagSys = DepDAG.prepare(packE.recipe("1.0.0"), config, services);
    dagSys.resolve();
    auto leaves = dagSys.collectResolvedLeaves();
    leaves.map!(l => l.name).should ~ ["a", "b"];

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), config, services, Heuristics.preferCache);

    string[] names = dag.traverseTopDown(Yes.root).map!(p => p.name.name).array;
    assert(names.length == 5);
    assert(names[0] == "e");
    assert(names.canFind("a", "b", "c", "d", "e"));

    names = dag.traverseTopDown(No.root).map!(p => p.name.name).array;
    assert(names.length == 4);
    assert(names.canFind("a", "b", "c", "d"));

    names = dag.traverseBottomUp(Yes.root).map!(p => p.name.name).array;
    assert(names.length == 5);
    assert(names[0] == "a");
    assert(names.canFind("a", "b", "c", "d", "e"));

    names = dag.traverseBottomUp(No.root).map!(p => p.name.name).array;
    assert(names.length == 4);
    assert(names[0] == "a");
    assert(names.canFind("a", "b", "c", "d"));

    dag.resolve();

    // preferCache: only a is a leave
    leaves = dag.collectResolvedLeaves();
    assert(leaves.length == 1);
    assert(leaves[0].name == "a");

    names = dag.traverseTopDownResolved(Yes.root).map!(n => n.pack.name.name).array;
    assert(names.length == 5);
    assert(names[0] == "e");
    assert(names.canFind("a", "b", "c", "d", "e"));

    names = dag.traverseBottomUpResolved(Yes.root).map!(n => n.pack.name.name).array;
    assert(names.length == 5);
    assert(names[0] == "a");
    assert(names.canFind("a", "b", "c", "d", "e"));
}

@("Test Heuristic.preferSystem")
unittest
{
    import std.algorithm : each;
    import std.typecons : Yes;

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    const heuristics = Heuristics.preferSystem;

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), config, services, heuristics);
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

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    const heuristics = Heuristics.preferCache;

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), config, services, heuristics);
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

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    const heuristics = Heuristics.preferLocal;

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), config, services, heuristics);
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

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    const heuristics = Heuristics.pickHighest;

    auto dag = DepDAG.prepare(packE.recipe("1.0.0"), config, services, heuristics);
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

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();
    const heuristics = Heuristics.preferSystem;

    auto dag1 = DepDAG.prepare(packE.recipe("1.0.0"), config, services, heuristics, Yes.preFilter);
    dag1.resolve();

    auto dag2 = DepDAG.prepare(packE.recipe("1.0.0"), config, services, heuristics, No.preFilter);
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

    auto resolved1 = mapNodeData(dag1.traverseTopDownResolved(Yes.root).array);
    auto resolved2 = mapNodeData(dag2.traverseTopDownResolved(Yes.root).array);

    assert(resolved1 == resolved2);
}

@("traverse without deps")
unittest
{
    import std.array : array;
    import std.typecons : Yes;

    auto pack = TestPackage("a", [
        TestPackVersion("1.0.1", [], DepLocation.cache)
    ], ["cc"]);
    auto services = buildMockDepServices([]);
    auto config = mockConfigLinux();

    auto dag = DepDAG.prepare(pack.recipe("1.0.1"), config, services);
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

@("Test not resolvable DAG")
unittest
{
    import std.exception : assertThrown;

    auto services = buildMockDepServices(testPackUnresolvable());
    auto config = mockConfigLinux();

    auto recipe = packNotResolvable.recipe("1.0.0");
    auto dag = DepDAG.prepare(recipe, config, services);

    assertThrown!UnresolvedDepException(dag.resolve());
}

@("Test DAG (de)serialization through JSON")
unittest
{
    import std.file : write;

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    auto recipe = packE.recipe("1.0.0");
    auto dag = DepDAG.prepare(recipe, config, services);
    dag.resolve();

    auto json = dag.toJson();
    auto dag2 = DepDAG.fromJson(json);

    assert(dag.toDot() == dag2.toDot());
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

private struct DependencyDrivenDownNodeRange
{
    import std.range : empty;
    import std.typecons : Flag;

@safe:

    private static struct TraceDownNode
    {
        DagNode node;
        uint edgei;

        bool valid() const
        {
            return edgei < node.downEdges.length;
        }

        @property inout(DagEdge) edge() inout
        {
            return node.downEdges[edgei];
        }

        void next()
        {
            edgei++;
        }

        @property bool hasNext() const
        {
            if (node.downEdges.empty)
                return false;
            return edgei < (node.downEdges.length - 1);
        }
    }

    TraceDownNode[] traceDown;

    DagNode above;
    uint edgei;
    DagNode currNode;
    DagNode[] visited;

    this(DagPack root, Flag!"root" visitRoot)
    {
        import std.algorithm : map;
        import std.array : array;

        currNode = root.resolvedNode;
        traceDown = [TraceDownNode(currNode, 0)];

        if (!visitRoot)
            popFront();
    }

    @property bool empty()
    {
        return currNode is null;
    }

    @property DagNode front()
    {
        return currNode;
    }

    void popFront()
    {
        currNode = null;

        if (traceDown.empty) // popFront called on empty range
            return;

        // check if we can continue from the bottom of trace
        if (checkBottomOfTrace())
            return;

        // otherwise unstack until a valid branch is found
        while (true)
        {
            traceDown = traceDown[0 .. $ - 1];
            if (traceDown.empty)
                break;
            if (checkBottomOfTrace())
                return;
        }
    }

    private bool checkBottomOfTrace()
    {
        // check if we can go one level down right away
        if (checkUnder())
            return true;

        // otherwise check the other edges at the same level
        while (traceDown[$ - 1].hasNext)
        {
            traceDown[$ - 1].next();
            if (checkUnder())
                return true;
        }

        return false;
    }

    private bool checkUnder()
    {
        auto td = traceDown[$ - 1];

        if (!td.valid)
            return false;

        auto edge = td.edge;
        auto down = edge.down.resolvedNode;

        if (wasVisited(down))
            return false;

        if (canBeVisited(down, edge))
        {
            currNode = down;
            visited ~= down;
            td.next();
            traceDown[$ - 1] = td;
            traceDown ~= TraceDownNode(down, 0);
            return true;
        }
        return false;
    }

    private bool canBeVisited(DagNode node, DagEdge from)
    {
        foreach (e; node.pack.upEdges)
        {
            if (e is from)
                continue;

            if (e.up !is e.up.pack.resolvedNode)
                continue;

            if (!wasVisited(e.up))
            {
                return false;
            }
        }

        return true;
    }

    private bool wasVisited(DagNode node)
    {
        foreach (n; visited)
        {
            if (n is node)
                return true;
        }
        return false;
    }
}

@("DependencyDrivenDownNodeRange with test graph")
unittest
{
    import std.algorithm;
    import std.typecons;
    import unit_threaded.assertions;

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();
    const heuristics = Heuristics.preferSystem;

    auto dag1 = DepDAG.prepare(packE.recipe("1.0.0"), config, services, heuristics, Yes.preFilter);
    dag1.resolve();
    dag1.traverseTopDownResolved(No.root).map!(n => n.name).should == [
        "b", "d", "c", "a"
    ];
    dag1.traverseTopDownResolved(Yes.root).map!(n => n.name)
        .should == [
            "e", "b", "d", "c", "a"
    ];

    auto dag2 = DepDAG.prepare(packE.recipe("1.0.0"), config, services, heuristics, No.preFilter);
    dag2.resolve();
    dag2.traverseTopDownResolved(No.root).map!(n => n.name).should == [
        "b", "d", "c", "a"
    ];
    dag2.traverseTopDownResolved(Yes.root).map!(n => n.name)
        .should == [
            "e", "b", "d", "c", "a"
    ];
}

@("DependencyDrivenDownNodeRange with vibe-d:http")
unittest
{
    import std.algorithm;
    import std.array;
    import std.json;
    import std.typecons;
    import unit_threaded.assertions;

    auto jsonLockStr = import("vibe-http-deps.json");
    auto jsonLock = parseJSON(jsonLockStr);
    auto dag = DepDAG.fromJson(jsonLock);

    auto rng = DependencyDrivenDownNodeRange(dag.root, No.root);
    rng.map!(n => n.name).should == [
        "vibe-d:http",
        "vibe-d:inet",
        "vibe-d:data",
        "vibe-d:textfilter",
        "vibe-d:tls",
        "vibe-d:stream",
        "vibe-d:utils",
        "openssl-static",
        "openssl",
        "vibe-d:crypto",
        "vibe-core",
        "eventcore",
        "taggedalgebraic",
        "stdx-allocator",
        "mir-linux-kernel",
        "diet-ng",
    ];
}

private struct DependencyDrivenUpNodeRange
{
    import std.range : empty;
    import std.typecons : Flag;

@safe:

    private static struct TraceUpPack
    {
        DagPack pack;
        uint edgei;

        bool hasNext() const
        {
            if (pack.upEdges.empty)
                return false;
            return edgei < (pack.upEdges.length - 1);
        }

        void next()
        {
            edgei++;
        }

        bool valid() const
        {
            return edgei < pack.upEdges.length;
        }

        @property inout(DagEdge) edge() inout
        {
            return pack.upEdges[edgei];
        }
    }

    private DagPack[] leaves;
    private TraceUpPack[] traceUp;

    private DagNode[] visited;
    private DagNode currNode;
    private Flag!"root" visitRoot;

    this(DagPack[] leaves, Flag!"root" visitRoot)
    {
        this.leaves = leaves;
        this.visitRoot = visitRoot;
        nextLeave();
    }

    @property bool empty()
    {
        return currNode is null;
    }

    @property DagNode front()
    {
        return currNode;
    }

    void popFront()
    {
        currNode = null;

        if (traceUp.empty) // popFront called on empty range
            return;

        // check if we can continue from the top of the trace
        if (checkTopOfTrace())
            return;

        // otherwise unstack until one is found
        while (true)
        {
            traceUp = traceUp[0 .. $ - 1];
            if (traceUp.empty)
                break;
            if (checkTopOfTrace())
                return;
        }

        // this trace is done, go to the next leave
        nextLeave();
    }

    private void nextLeave()
    {
        assert(traceUp.empty);

        if (leaves.empty)
            return;

        auto currPack = leaves[0];
        if (currPack.upEdges.empty && !visitRoot)
            return;

        leaves = leaves[1 .. $];
        traceUp = [TraceUpPack(currPack, 0)];
        visited ~= currPack.resolvedNode;
        currNode = currPack.resolvedNode;
    }

    private bool checkTopOfTrace()
    {
        // check if package above can be visited
        if (checkAbove())
            return true;

        // otherwise check the other edges at the same level
        while (traceUp[$ - 1].hasNext)
        {
            traceUp[$ - 1].next();
            if (checkAbove())
                return true;
        }

        return false;
    }

    private bool checkAbove()
    {
        auto tu = traceUp[$ - 1];
        if (!tu.valid)
            return false;

        auto edge = tu.edge;
        auto above = edge.up;
        if (canBeVisited(above, edge))
        {
            currNode = above;
            visited ~= above;
            tu.next();
            traceUp[$ - 1] = tu;
            traceUp ~= TraceUpPack(above.pack, 0);
            return true;
        }
        return false;
    }

    private bool canBeVisited(DagNode node, DagEdge from)
    {
        if (node.pack.isRoot && !visitRoot)
            return false;

        if (!node.isResolved)
            return false;

        // A node can be visited if all its dependencies
        // were visited before
        foreach (e; node.downEdges)
        {
            if (e is from)
                continue;

            if (!wasVisited(e.down.resolvedNode))
            {
                return false;
            }
        }

        return true;
    }

    private bool wasVisited(DagNode node)
    {
        foreach (n; visited)
        {
            if (n is node)
                return true;
        }
        return false;
    }
}

@("DependencyDrivenUpNodeRange with vibe-d:http")
unittest
{
    import std.algorithm;
    import std.array;
    import std.json;
    import std.typecons;
    import unit_threaded.assertions;

    auto jsonLockStr = import("vibe-http-deps.json");
    auto jsonLock = parseJSON(jsonLockStr);
    auto dag = DepDAG.fromJson(jsonLock);
    auto leaves = dag.collectResolvedLeaves();

    // Another leaves order is not necessarily incorrect
    // as long as all leaves are present.
    // But our test relies on the following order of leaves,
    // so we assert it before performing the actual test.
    leaves.map!(l => l.name).array.should == [
        "stdx-allocator",
        "taggedalgebraic",
        "openssl",
        "mir-linux-kernel",
        "diet-ng"
    ];

    auto rng = dag.traverseBottomUpResolved();

    rng.map!(n => n.name).should == [
        "stdx-allocator",
        "vibe-d:utils",
        "vibe-d:data",
        "taggedalgebraic",
        "eventcore",
        "vibe-core",
        "vibe-d:textfilter",
        "vibe-d:stream",
        "vibe-d:inet",
        "openssl",
        "openssl-static",
        "vibe-d:tls",
        "mir-linux-kernel",
        "vibe-d:crypto",
        "diet-ng",
        "vibe-d:http",
    ];
}

// dfmt off
version (unittest):

import dopamine.dep.source;

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

version (Windows)
{
    enum testPackDir = "C:\\DopTest";
}
else
{
    enum testPackDir = "/doptest";
}

struct TestPackage
{
    string name;
    TestPackVersion[] nodes;
    string[] tools;
    RecipeType type;

    RecipeDir recipe(string ver)
    {
        foreach (n; nodes)
        {
            if (n.ver == ver)
            {
                return RecipeDir(new MockRecipe(name, Semver(ver), type, "1",  n.deps, tools), testPackDir);
            }
        }
        assert(false, "wrong version");
    }
}

TestPackage[] testPackBase()
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
        ["cc"]
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
        ["dc"]
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
        ["c++"]
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
        ["dc"]
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
    ["dc"]
);

TestPackage[] testPackUnresolvable()
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
        ["cc"],
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
        ["cc"],
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
        ["cc"],
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
    ["cc"],
);

/// A mock Dependency Source
final class MockDepSource : DepSource
{
    TestPackage[string] packs;
    DepLocation loc;

    this (TestPackage[string] packs, DepLocation loc)
    {
        this.packs = packs;
        this.loc = loc;
    }

    Semver[] depAvailVersions(string name) @safe
    {
        auto pack = name in packs;
        if (!pack)
            return [];

        Semver[] res;
        foreach (n; pack.nodes)
        {
            if (n.loc == loc)
            {
                res ~= Semver(n.ver);
            }
        }
        return res;
    }

    bool hasPackage(string name, Semver ver, string rev) @safe
    {
        import std.algorithm : canFind;

        return depAvailVersions(name).canFind(ver);
    }

    /// get the recipe of a package
    RecipeDir depRecipe(string name, Semver ver, string rev = null) @system
    {
        import std.algorithm : find;
        import std.range : empty, front;

        auto pack = name in packs;
        if (!pack)
            return RecipeDir.init;

        auto pvR = pack.nodes.find!(pv => pv.aver == AvailVersion(ver, loc));
        if (pvR.empty)
            return RecipeDir.init;

        auto pv = pvR.front;

        const revision = rev ? rev : "1";
        return RecipeDir(new MockRecipe(name, ver, pack.type, revision, pv.deps, pack.tools), testPackDir);
    }

    @property bool hasDepDependencies()
    {
        return false;
    }

    const(DepSpec)[] depDependencies(const(BuildConfig) config, string name, Semver ver, string rev = null)
    {
        assert(false, "Not implemented");
    }
}

DepService buildMockDepService(TestPackage[] packs)
{
    import std.algorithm : map;
    import std.array : assocArray;
    import std.typecons : tuple;

    TestPackage[string] aa = packs.map!(p => tuple(p.name, p)).assocArray;

    return new DepService(
        new MockDepSource(aa, DepLocation.system),
        new MockDepSource(aa, DepLocation.cache),
        new MockDepSource(aa, DepLocation.network),
    );
}

DepServices buildMockDepServices(TestPackage[] packs)
{
    return DepServices(
        buildMockDepService(packs),
        buildMockDepService(packs),
    );
}
