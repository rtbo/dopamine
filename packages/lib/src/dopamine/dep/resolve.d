/// Dependency resolution module.
///
/// The resolution is performed with 2 distinct data structures:
///     - Intermediate dependency graph
///     - Resolved dependency graph
///
/// Both are directed acyclic graphs.
///
/// The intermediate dependency graph performs all the heavy lifting of the resolution.
/// It carries temporary data and is mutated along the resolution steps.
/// It is composed of the following types:
///     - [IgPack]: corresponds to a package and gathers several [IgNode] versions.
///     - [IgNode]: corresponds to a package version, that express dependencies towards other packages.
///     - [IgEdge]: corresponds to a dependency specification and connect one [IgNode] to one [IgPack] dependency.
///       An [IgEdge] starts from a [IgNode] and points towards an [IgPack].
///
/// The resolved dependency graph describes a fully resolved dependency tree, and is essentially a simpler and
/// immutable data structure that is designed to be serialized/deserialized in a lock file.
/// It is composed of the following types:
///     - [DgNode]: corresponds to a resolved package version and revision.
///     - [DgEdge]: corresponds to a version specification and connects a [DgNode] package to a [DgNode] dependency.
///
/// Code not interested in the intermediate graph should use the `resolveDependencies` function, which handles everything.
///
/// The directions _up_ and _down_ used in this module refer to the following:
///     - The graph root is at the top. This is the package for which dependencies are resolved.
///     - The graph leaves are at the bottom. These are the dependencies that do not have dependencies themselves.
///
/// The strategy of resolution is dictated by the [Heuristics] struct.
module dopamine.dep.resolve;

import dopamine.dep.lock;
import dopamine.dep.service;
import dopamine.dep.spec;
import dopamine.recipe;
import dopamine.semver;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.json;
import std.typecons;

@safe:

/// Heuristics helps choosing a package version in a set of compatible versions.
/// By default, we always prefer to use what is available locally and allow to use
/// packages installed in the user system.
/// Pre-selected versions can also be specified to force the selection of a specifc version for a package.
struct Heuristics
{
    /// Mode to define if we prefer to re-use what is available locally
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
    const(string)[] systemList;
    const(Semver[string]) preSelected;

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
        return Heuristics(mode, System.allow, systemList, preSelected);
    }

    Heuristics withSystemDisallowed() const
    {
        return Heuristics(mode, System.disallow, systemList, preSelected);
    }

    Heuristics withSystemAllowedList(const(string)[] allowedSystemList) const
    {
        return Heuristics(mode, System.allowedList, allowedSystemList, preSelected);
    }

    Heuristics withSystemDisallowedList(const(string)[] disallowedSystemList) const
    {
        return Heuristics(mode, System.disallowedList, disallowedSystemList, preSelected);
    }

    /// Check whether the provided [AvailVersion] of [packname] is compatible
    /// with this heuristics.
    bool allow(string packname, AvailVersion aver) const
    {
        if (const(Semver)* ver = packname in preSelected)
            return *ver == aver.ver;

        if (!aver.location.isSystem)
            return true;

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
    AvailVersion chooseVersion(string packname, const(AvailVersion)[] compatibleVersions) const @safe
    in (compatibleVersions.length > 0)
    {
        // check pre-selected
        if (const(Semver)* ver = packname in preSelected)
        {
            foreach (av; compatibleVersions.filter!(av => av.location.isCache))
            {
                if (av.ver == *ver)
                    return av;
            }
            foreach (av; compatibleVersions.filter!(av => av.location.isNetwork))
            {
                if (av.ver == *ver)
                    return av;
            }
            throw new Exception("Can't find pre-selected version " ~ packname ~ "/" ~ ver.toString());
        }

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

    static Heuristics fromJson(JSONValue json) @safe
    {
        const mode = json["mode"].str.to!Mode;
        const system = json["system"].str.to!System;
        auto systemList = json["systemList"].arrayNoRef.map!(jv => jv.str).array;
        return Heuristics(mode, system, systemList);
    }

    JSONValue toJson() const @safe
    {
        import std.conv : to;

        JSONValue[string] json;
        json["mode"] = mode.to!string;
        json["system"] = system.to!string;
        json["systemList"] = JSONValue(systemList);
        return JSONValue(json);
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

    assert(heuristicsSys.chooseVersion("depname", compatibleVersions1) ==
            AvailVersion(Semver("3.0.0"), DepLocation.system));
    assert(heuristicsSys.chooseVersion("depname", compatibleVersions2) ==
            AvailVersion(Semver("2.0.0"), DepLocation.system));
    assert(heuristicsSys.chooseVersion("depname", compatibleVersions3) ==
            AvailVersion(Semver("1.0.0"), DepLocation.system));

    assert(heuristicsCache.chooseVersion("depname", compatibleVersions1) ==
            AvailVersion(Semver("3.0.0"), DepLocation.cache));
    assert(heuristicsCache.chooseVersion("depname", compatibleVersions2) ==
            AvailVersion(Semver("1.0.0"), DepLocation.cache));
    assert(heuristicsCache.chooseVersion("depname", compatibleVersions3) ==
            AvailVersion(Semver("2.0.0"), DepLocation.cache));

    assert(heuristicsLocal.chooseVersion("depname", compatibleVersions1) ==
            AvailVersion(Semver("3.0.0"), DepLocation.cache));
    assert(heuristicsLocal.chooseVersion("depname", compatibleVersions2) ==
            AvailVersion(Semver("2.0.0"), DepLocation.system));
    assert(heuristicsLocal.chooseVersion("depname", compatibleVersions3) ==
            AvailVersion(Semver("2.0.0"), DepLocation.cache));

    assert(heuristicsHighest.chooseVersion("depname", compatibleVersions1) ==
            AvailVersion(Semver("3.0.0"), DepLocation.cache));
    assert(heuristicsHighest.chooseVersion("depname", compatibleVersions2) ==
            AvailVersion(Semver("3.0.0"), DepLocation.network));
    assert(heuristicsHighest.chooseVersion("depname", compatibleVersions3) ==
            AvailVersion(Semver("3.0.0"), DepLocation.network));
    // dfmt on
}

class UnresolvedDepException : Exception
{
    private this(IgPack pack, IgPack[] ups, string file = __FILE__, size_t line = __LINE__)
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
                .find!(e => e.up.pack is up)
                .front
                .spec;

            app.put(format(" - %s depends on %s %s\n", up.name, pack.name, spec));
        }

        super(app.data, file, line);
    }
}

/// Dependency Graph node
/// Represent a resolved package version
final class DgNode
{
public:
    /// The name of this package
    @property PackageName name() const pure
    {
        return _name;
    }

    /// The kind of this package
    @property DepKind kind() const pure
    {
        return _kind;
    }

    /// The package version and location of this node
    @property AvailVersion aver() const pure
    {
        return _aver;
    }

    /// The package version of this node
    @property Semver ver() const pure
    {
        return _aver.ver;
    }

    /// The location of this package
    @property DepLocation location() const pure
    {
        return _aver.location;
    }

    /// The revision of this package.
    @property string revision() const pure
    {
        return _revision;
    }

    /// The dependencies specified by this package
    @property const(DepSpec)[] deps() const
    {
        return _deps;
    }

    /// The options for this node coming from the top of the graph.
    @property const(OptionSet) options() const
    {
        return _options;
    }

    /// The conflicting options remaining for this node.
    /// If not empty, more options must be
    /// provided externally to resolve these options.
    /// See_Also: dopamine.dep.build.buildDependencies
    @property const(string)[] optionConflicts() const
    {
        return _optionConflicts;
    }

    /// The edges going to node depending on this package
    @property const(DgEdge)[] upEdges() const
    {
        return _upEdges;
    }

    /// The edges going to dependencies of this package
    @property const(DgEdge)[] downEdges() const
    {
        return _downEdges;
    }

    /// Is this node the graph root?
    @property bool isRoot() const
    {
        return upEdges.length == 0;
    }

package(dopamine.dep):

    PackageName _name;
    DepKind _kind;
    AvailVersion _aver;
    string _revision;
    const(DepSpec)[] _deps;
    OptionSet _options;
    string[] _optionConflicts;

    DgEdge[] _upEdges;
    DgEdge[] _downEdges;

    // used in lock.d
    this()
    {
    }

    this(const(IgNode) node)
    {
        _name = PackageName(node.pack.name);
        _kind = node.pack.kind;
        _aver = node.aver;
        _revision = node.revision;
        _deps = node.deps;
        _options = node.options.dup;
        _optionConflicts = node.optionConflicts.dup;
    }
}

/// Dependency Graph edge
/// Connects a package to a dependency through a version specification.
final class DgEdge
{
public:
    @property const(DgNode) up() const
    {
        return _up;
    }

    @property const(DgNode) down() const
    {
        return _down;
    }

    @property VersionSpec spec() const
    {
        return _spec;
    }

package(dopamine.dep):

    DgNode _up;
    DgNode _down;
    VersionSpec _spec;
}

/// Resolved dependency graph
struct DepGraph
{
    @property const(DgNode) root() const
    {
        return _root;
    }

    @property const(ResolveConfig) config() const
    {
        return _config;
    }

    static DepGraph fromJson(JSONValue json)
    {
        return jsonToDepGraph(json);
    }

    JSONValue toJson(int lockVersion = currentLockVersion) const @safe
    {
        return depGraphToJson(this, lockVersion);
    }

    auto traverseTopDown(Flag!"root" traverseRoot = No.root)
    {
        return dgTraverseTopDown(root, traverseRoot);
    }

    auto traverseBottomUp(Flag!"root" traverseRoot = No.root)
    {
        return dgTraverseBottomUp(root, traverseRoot);
    }

private:
    const(DgNode) _root;
    const(ResolveConfig) _config;
}

/// Return a range that traverses a dependency tree downwards.
/// It ensures that each package is traversed before its dependencies.
auto dgTraverseTopDown(const(DgNode) root, Flag!"root" traverseRoot = No.root)
{
    return DependencyDrivenDownNodeRange(root, traverseRoot);
}

/// Return a range that traverses a dependency tree upwards.
/// It ensures that each package is traversed after all its dependencies.
auto dgTraverseBottomUp(const(DgNode) root, Flag!"root" traverseRoot = No.root)
{
    const leaves = dgCollectLeaves(root);
    return dgTraverseBottomUp(root, leaves, traverseRoot);
}

/// ditto
auto dgTraverseBottomUp(const(DgNode) root, const(DgNode)[] leaves, Flag!"root" traverseRoot = No
    .root)
{
    return DependencyDrivenUpNodeRange(leaves, traverseRoot);
}

const(DgNode)[] dgCollectLeaves(const(DgNode) root)
{
    const(DgNode)[] traversed;
    const(DgNode)[] leaves;

    void traverse(inout(DgNode) node) @safe
    {
        if (traversed.canFind!"a is b"(node))
            return;
        traversed ~= node;

        bool isLeaf = true;
        foreach (edge; node.downEdges)
        {
            traverse(edge.down);
            isLeaf = false;
        }
        if (isLeaf)
            leaves ~= node;
    }

    traverse(root);

    return leaves;
}

/// Print a GraphViz' DOT representation of the resolved graph
void dgToDot(O)(const(DgNode) root, ref O output)
{
    int indent = 0;

    void line(Args...)(string lfmt, Args args) @safe
    {
        static if (Args.length == 0)
        {
            output.put(replicate("  ", indent) ~ lfmt ~ "\n");
        }
        else
        {
            output.put(replicate("  ", indent) ~ format(lfmt, args) ~ "\n");
        }
    }

    void emptyLine() @safe
    {
        output.put("\n");
    }

    void block(string header, void delegate() dg) @trusted
    {
        line(header ~ " {");
        indent += 1;
        dg();
        indent -= 1;
        line("}");
    }

    string[const(DgNode)] nodeKeys;

    string key(const(DgNode) node)
    {
        if (auto k = node in nodeKeys)
            return *k;
        const newK = format!"node_%s"(nodeKeys.length + 1);
        nodeKeys[node] = newK;
        return newK;
    }

    block("digraph G", {
        emptyLine();
        line("node [shape=box ranksep=1];");
        emptyLine();

        foreach (node; root.dgTraverseTopDown(Yes.root))
        {
            string label = node.name.name;
            if (node.kind.isDub)
                label ~= " (DUB)";
            label ~= format!"\\n%s (%s)"(node.ver, node.aver.location);
            line(`%s [label="%s"]`, key(node), label);
        }

        emptyLine();

        foreach (node; root.dgTraverseTopDown(Yes.root))
        {
            foreach (edge; node.downEdges)
            {
                line(`%s -> %s [label=" %s  "]`,
                    key(edge.up),
                    key(edge.down),
                    edge.spec.toString(),
                );
            }
        }
    });
}

void dgToDotFile(const(DgNode) root, string filename)
{
    import std.file : write;

    auto output = appender!string;
    root.dgToDot(output);
    write(filename, output.data);
}

void dgToDotPng(const(DgNode) root, string filename)
{
    import std.process : pipeProcess, Redirect;

    auto output = appender!string;
    root.dgToDot(output);

    const cmd = ["dot", "-Tpng", "-o", filename];
    auto pipes = pipeProcess(cmd, Redirect.stdin);

    pipes.stdin.write(output.data);
}

/// Resolve dependencies for the given recipe.
///
/// This function returns a resolved dependency graph with the main recipe at the root.
///
/// Params:
///   recipe = Recipe from the root package
///   services = The dependency service to fetch available versions and recipes.
///   heuristics = The Heuristics to select the dependencies.
///   config = The dependency resolution configuration
///
/// Returns: a resolved [DepGraph]
DepGraph resolveDependencies(
    RecipeDir rdir, const(ResolveConfig) config,
    DepServices services, const(Heuristics) heuristics = Heuristics.init) @system
{
    auto ig = igPrepare(rdir, config, services, heuristics);
    igResolve(ig, services, heuristics);

    return DepGraph(dgCreate(ig), config);
}

/// Create a resolved graph from the intermediate graph.
/// The intermediate graph must be fully resolved.
DgNode dgCreate(IgPack root)
in (igIsResolved(root))
{
    void createNodes(IgNode igNode) @safe
    {
        assert(igNode, "dgCreate must be called with a resolved intermediate graph");

        if (igNode.dgNode)
            return;

        auto dgNode = new DgNode(igNode);
        igNode.dgNode = dgNode;

        foreach (edge; igNode.downEdges)
            createNodes(edge.down.resolvedNode);
    }

    void createEdges(IgNode igNode) @safe
    {
        if (igNode.dgEdgesDone)
            return;

        igNode.dgEdgesDone = true;

        foreach (e; igNode.downEdges)
        {
            auto up = igNode.dgNode;
            auto down = e.down.resolvedNode.dgNode;

            auto edge = new DgEdge;
            edge._up = up;
            edge._down = down;
            edge._spec = e.spec;
            up._downEdges ~= edge;
            down._upEdges ~= edge;

            createEdges(e.down.resolvedNode);
        }
    }

    void cleanUp(IgNode igNode) @safe
    {
        if (!igNode.dgNode)
            return;

        igNode.dgNode = null;

        foreach (e; igNode.downEdges)
            cleanUp(e.down.resolvedNode);
    }

    createNodes(root.resolvedNode);
    createEdges(root.resolvedNode);

    auto dgRoot = root.resolvedNode.dgNode;

    cleanUp(root.resolvedNode);

    return dgRoot;
}

/// Intermediate graph package
final class IgPack
{
public:
    @property string name() const
    {
        return _name;
    }

    @property DepKind kind() const
    {
        return _kind;
    }

    @property const(AvailVersion)[] compatVersions() const
    {
        if (superPack)
            return superPack._compatVersions;
        return _compatVersions;
    }

    @property const(AvailVersion)[] consideredVersions() const
    {
        return _nodes.map!(n => n.aver).array;
    }

    /// Each node represent a version of this package
    @property inout(IgNode)[] nodes() inout
    {
        return _nodes;
    }

    /// Edges to nodes depending on this package
    @property inout(IgEdge)[] upEdges() inout
    {
        return _upEdges;
    }

    /// Get existing node that match with [ver], or null
    inout(IgNode) getNode(const(AvailVersion) aver) inout
    {
        foreach (n; _nodes)
        {
            if (n.aver == aver)
                return n;
        }
        return null;
    }

    /// Get the node resolved for this package
    @property inout(IgNode) resolvedNode() inout
    {
        return _resolvedNode;
    }

private:

    string _name;
    DepKind _kind;
    // versions compatible with current resolution level
    AvailVersion[] _compatVersions;

    IgNode[] _nodes;
    IgEdge[] _upEdges;

    // options cumulated from all nodes
    OptionSet[] options;
    // versions cached from the service
    AvailVersion[] versionsCached;
    // if this is a submodule package, have a reference to the super package
    IgPack superPack;
    // if this has submodule packages, their list is here
    IgPack[] modPacks;

    // The node eventually resolved for this package
    IgNode _resolvedNode;

    this(string name, DepKind kind)
    {
        _name = name;
        _kind = kind;
    }

    static IgPack makeRoot(const(Recipe) recipe)
    {
        auto root = new IgPack(recipe.name, recipe.type.toDepKind);
        root.addCompatVersions([AvailVersion(recipe.ver, DepLocation.cache)]);
        return root;
    }

    void addCompatVersions(AvailVersion[] avs) @trusted
    {
        import std.algorithm : sort, uniq;
        import std.array : array;

        if (superPack)
        {
            superPack.addCompatVersions(avs);
        }
        else
        {
            _compatVersions ~= avs;
            _compatVersions = sort(_compatVersions).uniq().array;
        }
    }

    /// Get node that match with [ver]
    /// Create one if doesn't exist
    IgNode getOrCreateNode(const(AvailVersion) aver) @safe
    {
        foreach (n; _nodes)
        {
            if (n.aver == aver)
                return n;
        }

        auto node = new IgNode(this, aver);
        _nodes ~= node;

        // for submodules, create the same node for the same version
        // for each module in the super package.
        assert(!(superPack && modPacks.length), "Can't be root and non-root at the same time");
        if (superPack)
            superPack.getOrCreateNode(aver);
        foreach (mp; modPacks)
            mp.getOrCreateNode(aver);

        return node;
    }

    @property void resolvedNode(IgNode node)
    {
        assert(node.pack is this);
        _resolvedNode = node;
    }
}

/// Intermediate graph node
final class IgNode
{
public:

    /// The package owner of this version node
    @property inout(IgPack) pack() inout
    {
        return _pack;
    }

    /// The name of this package
    @property string name() const
    {
        return _pack.name;
    }

    /// The kind of this package
    @property DepKind kind() const
    {
        return _pack.kind;
    }

    /// The package version and location of this node
    @property AvailVersion aver() const
    {
        return _aver;
    }

    /// The package version of this node
    @property Semver ver() const
    {
        return _aver.ver;
    }

    /// The revision of this package.
    @property string revision() const
    {
        return _revision;
    }

    /// The dependencies specified by this package
    @property const(DepSpec)[] deps() const
    {
        return _deps;
    }

    /// The options for this node coming from the top of the graph.
    /// This field is populated only once the graph is resolved.
    @property const(OptionSet) options() const
    {
        return _options;
    }

    /// The conflicting options remaining for this node
    /// If not empty after dependency resolution, more options must be
    /// provided externally to resolve these options
    @property const(string)[] optionConflicts() const
    {
        return _optionConflicts;
    }

    /// The edges going to dependencies of this package
    @property inout(IgEdge)[] downEdges() inout
    {
        return _downEdges;
    }

    /// Whether this node is the resolved node of its package
    @property bool isResolved() const
    {
        return _pack && _pack._resolvedNode is this;
    }

private:

    IgPack _pack;
    AvailVersion _aver;
    string _revision;
    OptionSet _options;
    string[] _optionConflicts;
    const(DepSpec)[] _deps;
    IgEdge[] _downEdges;

    /// The DgNode created for this IgNode
    DgNode dgNode;

    /// Whether the DgEdges were created for this IgNode
    bool dgEdgesDone;

    this(IgPack pack, AvailVersion aver)
    {
        _pack = pack;
        _aver = aver;
    }
}

/// Intermediate graph edge
final class IgEdge
{
public:
    @property inout(IgNode) up() inout
    {
        return _up;
    }

    @property inout(IgPack) down() inout
    {
        return _down;
    }

    @property VersionSpec spec() const
    {
        return _spec;
    }

    @property bool onResolvedPath() const
    {
        return _up && _up.isResolved && _down && _down.resolvedNode !is null;
    }

private:
    IgNode _up;
    IgPack _down;
    VersionSpec _spec;

    static void create(IgNode up, IgPack down, VersionSpec spec)
    {
        auto edge = new IgEdge;

        edge._up = up;
        edge._down = down;
        edge._spec = spec;

        up._downEdges ~= edge;
        down._upEdges ~= edge;
    }
}

/// Package unique id from name and kind.
/// Used in intermediate graph preparation.
package(dopamine.dep) string packKey(string name, DepKind kind) pure @safe
{
    import std.format : format;

    return format!"%s__%s"(kind, name);
}

/// ditto
package(dopamine.dep) string packKey(const(DgNode) node) pure @safe
{
    return packKey(node.name.name, node.kind);
}

/// First phase of dependency resolution.
/// Build the main intermediate graph with all versions compatible with dependency specs.
/// Params:
///   recipe = Recipe from the root package
///   services = The dependency service to fetch available versions and recipes.
///   heuristics = The `Heuristics` to select the dependencies.
///   config = The dependency resolution configuration
/// Returns: The root of the graph.
IgPack igPrepare(RecipeDir rootRdir,
    const(ResolveConfig) config,
    DepServices services,
    const(Heuristics) heuristics = Heuristics.init) @system
{
    IgPack[string] packs;

    IgPack preparePack(const(DepSpec) dep)
    {
        auto service = services[dep.kind];

        const superName = dep.name.pkgName;
        const superId = packKey(superName, dep.kind);
        auto superPack = packs.get(superId, null);
        if (!superPack)
        {
            superPack = new IgPack(superName, dep.kind);
            superPack.versionsCached = service.packAvailVersions(dep.name);
            packs[superId] = superPack;
        }

        IgPack pack;
        if (superName == dep.name)
        {
            pack = superPack;
        }
        else
        {
            // sub-module
            const id = packKey(dep.name, dep.kind);
            pack = packs.get(id, null);
            if (!pack)
            {
                pack = new IgPack(dep.name, dep.kind);
                pack.superPack = superPack;
                superPack.modPacks ~= pack;
                packs[id] = pack;
            }
        }

        auto compatAvs = superPack.versionsCached
            .filter!(av => dep.spec.matchVersion(av.ver))
            .filter!(av => heuristics.allow(dep.name, av))
            .array;

        pack.addCompatVersions(compatAvs);
        pack.options ~= dep.options.dup;

        return pack;
    }

    auto root = IgPack.makeRoot(rootRdir.recipe);
    IgNode[] visited;

    struct RecipeInfo
    {
        string name;
        DepKind kind;
    }

    void doPackVersion(RecipeInfo rinfo, IgPack pack, AvailVersion aver)
    {
        auto node = pack.getOrCreateNode(aver);

        if (visited.canFind(node))
            return;
        visited ~= node;

        if (pack is root)
        {
            node._deps = rootRdir.recipe.dependencies(config);
        }
        else
        {
            auto service = services[rinfo.kind];
            node._deps = service.packDependencies(config, rinfo.name, aver);
        }

        foreach (dep; node.deps)
        {
            auto service = services[dep.kind];

            auto ip = preparePack(dep);
            IgEdge.create(node, ip, dep.spec);

            foreach (dv; ip.compatVersions)
            {
                // stop recursion for system dependencies
                if (dv.location.isSystem)
                {
                    // ensure node is created before stopping
                    auto dn = ip.getOrCreateNode(dv);
                    if (!visited.canFind!"a is b"(dn))
                        visited ~= dn;

                    continue;
                }

                doPackVersion(RecipeInfo(dep.name, dep.kind), ip, dv);
            }
        }
    }

    const rootInfo = RecipeInfo(rootRdir.recipe.name, rootRdir.recipe.type.toDepKind);

    doPackVersion(rootInfo, root, root.compatVersions[0]);

    return root;
}

/// Final phase of resolution to eliminate incompatible versions
/// and attribute a resolved version to each package.
///
/// Throws:
/// UnresolvedDepException if a dependency cannot be resolved to a single version.
void igResolve(IgPack root, DepServices services, const(Heuristics) heuristics = Heuristics.init) @system
in (root.nodes.length == 1)
{
    void resolveDeps(IgPack pack) @system
    {
        assert(pack.resolvedNode);

        foreach (dep; pack.resolvedNode.downEdges.map!(e => e.down))
        {
            if (dep.resolvedNode)
                continue;

            auto service = services[dep.kind];

            if (dep.superPack && dep.superPack.resolvedNode)
            {
                // for submodule, assign the version resolved for the super package
                const resolved = dep.superPack.resolvedNode.aver;
                auto rn = dep.getNode(resolved);
                assert(rn, "Version discrepancy between submodule and its super-package");
                string revision = dep.superPack.resolvedNode.revision;
                if (!revision.length && dep.kind.isDop)
                {
                    auto rdir = service.packRecipe(dep.superPack.name, rn.aver);
                    revision = rdir.recipe.revision;
                    dep.superPack._resolvedNode._revision = revision;
                }
                rn._revision = revision;
                dep.resolvedNode = rn;
            }
            else
            {
                // regular case
                const consideredVersions = dep.nodes.map!(n => n.aver).array;
                const resolved = heuristics.chooseVersion(dep.name, consideredVersions);
                auto rn = dep.getNode(resolved);
                assert(rn);
                if (dep.kind.isDop && !resolved.location.isSystem)
                {
                    auto rdir = service.packRecipe(dep.name, rn.aver);
                    rn._revision = rdir.recipe.revision;
                }
                dep.resolvedNode = rn;
            }

            resolveDeps(dep);
        }
    }

    igCheckCompat(root);

    root.resolvedNode = root.nodes[0];
    resolveDeps(root);

    igCascadeOptions(root);
}

// 2nd phase of filtering to eliminate all incompatible versions in the DAG.
// This algorithm will typically handle some special cases, like diamond layout or such.
//
// Throws: UnresolvedDepException
private void igCheckCompat(IgPack root)
{
    // dumb compatibility check in bottom-up direction
    // we simply loop until nothing more changes

    auto leaves = igCollectLeaves(root);

    while (1)
    {
        bool diff;
        foreach (pack; igTraverseBottomUp(root, leaves, No.root))
        {
            // Remove nodes of pack for which at least one up package is found
            // without compatibility with it
            IgPack[] ups;
            foreach (e; pack._upEdges)
            {
                if (!ups.canFind!"a is b"(e.up.pack))
                {
                    ups ~= e.up.pack;
                }
            }

            size_t ni;
            while (ni < pack.nodes.length)
            {
                auto node = pack.nodes[ni];
                bool rem;

                foreach (up; ups)
                {
                    // check if `node` is compatible with at least one version of `up`
                    // (no dependency to `node` also mean compatible)

                    bool compat;

                    foreach (un; up.nodes)
                    {
                        auto downToPack = un.downEdges
                            .filter!(e => e.down is pack);

                        const nodep = downToPack.empty;
                        const comp = downToPack.any!(e => e.spec.matchVersion(node.ver));

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
                    pack._nodes = pack._nodes.remove!(n => n.aver == node.aver);
                    foreach (e; node.downEdges)
                        e.down._upEdges = e.down._upEdges.remove!(ue => ue is e);
                }
                else
                {
                    ni++;
                }
            }

            enforce(pack.nodes.length > 0, new UnresolvedDepException(pack, ups));
        }

        if (!diff)
            break;
    }
}

private void igCascadeOptions(IgPack root)
{
    OptionSet remaining;
    string[] remainingConflicts;

    void doPack(IgPack pack) @safe
    {
        auto rn = pack.resolvedNode;

        // Initialize node options and conflicts with those
        // from previous node that are targetting it.
        // Used remaining options are cleaned up.
        const prefix = pack.name ~ "/";
        rn._options = remaining.forDependency(pack.name);
        remaining = remaining.notFor(pack.name);
        foreach (c; remainingConflicts)
        {
            if (c.startsWith(prefix))
                rn._optionConflicts ~= c[prefix.length .. $];
        }

        foreach (opt; pack.options)
        {
            rn._options = rn._options.merge(rn._optionConflicts, opt.forRoot(), opt.forDependency(
                    pack.name));
            remaining = remaining.merge(remainingConflicts, opt.notFor(pack.name));
        }

        foreach (IgEdge e; rn.downEdges)
        {
            doPack(e.down);
        }
    }

    doPack(root);

    if (remaining.length)
    {
        import dopamine.log : logWarningH;

        logWarningH(
            "Some options were defined but not used in the dependency graph:\n - ",
            remaining.keys.join("\n - ")
        );
    }
}

bool igIsResolved(const(IgPack) root)
{
    return root
        .igTraverseTopDown(Yes.root)
        .all!(p => p.resolvedNode !is null);
}

inout(IgPack)[] igCollectLeaves(inout(IgPack) root)
{
    inout(IgPack)[] traversed;
    inout(IgPack)[] leaves;

    void traverse(inout(IgPack) pack) @safe
    {
        if (traversed.canFind!"a is b"(pack))
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
            leaves ~= pack;
    }

    traverse(root);

    return leaves;
}

/// Returns a range over all packages (aka `IgPack`) of dependency intermediate graph.
/// The graph is iterated from the top (root) to the bottom (leaves).
auto igTraverseTopDown(IgPack root, Flag!"root" traverseRoot = No.root)
{
    auto res = IgDepthFirstTopDownRange!IgPack([root]);

    if (!traverseRoot)
        res.popFront();

    return res;
}

/// ditto
auto igTraverseTopDown(const(IgPack) root, Flag!"root" traverseRoot = No.root)
{
    auto res = IgDepthFirstTopDownRange!(const(IgPack))([root]);

    if (!traverseRoot)
        res.popFront();

    return res;
}

/// Returns a range over all packages (aka `IgPack`) of dependency intermediate graph.
/// The graph is iterated from the bottom (leaves) to the top (root).
auto igTraverseBottomUp(IgPack root, IgPack[] leaves, Flag!"root" traverseRoot)
{
    if (!traverseRoot && leaves.length == 1 && leaves[0] is root)
    {
        return IgDepthFirstBottomUpRange!IgPack([]);
    }

    auto res = IgDepthFirstBottomUpRange!IgPack(leaves);

    if (!traverseRoot)
        res.visited ~= root;

    return res;
}

/// ditto
auto igTraverseBottomUp(const(IgPack) root, const(IgPack)[] leaves, Flag!"root" traverseRoot)
{
    if (!traverseRoot && leaves.length == 1 && leaves[0] is root)
    {
        return IgDepthFirstBottomUpRange!(const(IgPack))([]);
    }

    auto res = IgDepthFirstBottomUpRange!(const(IgPack))(leaves);

    if (!traverseRoot)
        res.visited ~= root;

    return res;
}

/// Options for the GraphViz export feature of Intermediate Graph
enum IgDot
{
    /// Only show the resolved nodes
    resolvedOnly = 0,
    /// Include versions that are compatible, but not chosen as "resolved"
    includeCompat = 1,
    /// Include all versions, including those not compatible with dependency graph
    includeAll = 3,
}

/// Print a GraphViz' DOT representation of the intermediate graph
void igToDot(O)(const(IgPack) root, ref O output, IgDot options = IgDot.includeCompat)
{
    int indent = 0;

    void line(Args...)(string lfmt, Args args) @safe
    {
        static if (Args.length == 0)
        {
            output.put(replicate("  ", indent) ~ lfmt ~ "\n");
        }
        else
        {
            output.put(replicate("  ", indent) ~ format(lfmt, args) ~ "\n");
        }
    }

    void emptyLine() @safe
    {
        output.put("\n");
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
        return format!"%s-%s-%s"(packname, aver.ver, aver.location);
    }

    string nodeGName(string packname, const(AvailVersion) aver) @safe
    {
        const id = nodeId(packname, aver);
        const res = nodeGNames[id];
        assert(res, "unprocessed version: " ~ id);
        return res;
    }

    const printAll = (options & IgDot.includeAll) == IgDot.includeAll;
    const printCompat = (options & IgDot.includeCompat) == IgDot.includeCompat;

    block("digraph G", {
        emptyLine();
        line("graph [compound=true ranksep=1];");
        emptyLine();

        // write clusters / pack
        foreach (pack; igTraverseTopDown(root, Yes.root))
        {
            const name = format("cluster_%s", packNum++);
            packGNames[pack.name] = name;

            const(AvailVersion)[] allVersions = pack.compatVersions;
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
            emptyLine();
        }

        // write edges
        foreach (pack; igTraverseTopDown(root, Yes.root))
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
                    else if (e.down.compatVersions.length)
                    {
                        props ~= "color=\"crimson\"";
                        downNode = e.down.compatVersions[0];
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
}

/// Print a GraphViz' DOT representation of the graph to a Dot file
void igToDotFile(const(IgPack) root, string filename, IgDot options = IgDot.includeCompat)
{
    import std.file : write;

    auto output = appender!string;
    root.igToDot(output, options);
    write(filename, output.data);
}

/// Write a GraphViz' DOT representation of the graph directly to a Png file.
/// Requires the `dot` command line tool to be in the PATH
void igToDotPng(const(IgPack) root, string filename, IgDot options = IgDot.includeCompat)
{
    import std.process : pipeProcess, Redirect;

    auto output = appender!string;
    root.igToDot(output, options);

    const cmd = ["dot", "-Tpng", "-o", filename];
    auto pipes = pipeProcess(cmd, Redirect.stdin);

    pipes.stdin.write(output.data);
}

private:

/// Range that traverse a dependency tree downwards.
/// It ensures that each package is traversed before its dependencies.
private struct DependencyDrivenDownNodeRange
{
    import std.range : empty;
    import std.typecons : Flag;

@safe:

    private static struct TraceDownNode
    {
        Rebindable!(const(DgNode)) node;
        uint edgei;

        bool valid() const
        {
            return edgei < node.downEdges.length;
        }

        @property const(DgEdge) edge() const
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

    const(DgNode) root;
    const(DgNode) above;
    uint edgei;
    Rebindable!(const(DgNode)) currNode;
    const(DgNode)[] visited;

    this(const(DgNode) root, Flag!"root" visitRoot)
    {
        import std.algorithm : map;
        import std.array : array;

        this.root = root;
        this.currNode = root;
        this.traceDown = [TraceDownNode(currNode, 0)];

        if (!visitRoot)
            popFront();
    }

    @property bool empty() const
    {
        return currNode is null;
    }

    @property const(DgNode) front() const
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
        auto down = edge.down;

        if (wasVisited(down))
            return false;

        if (canBeVisited(down, edge))
        {
            currNode = down;
            visited ~= down;
            td.next();
            traceDown[$ - 1] = td;
            traceDown ~= TraceDownNode(rebindable(down), 0);
            return true;
        }
        return false;
    }

    private bool linksToRoot(const(DgNode) node)
    {
        if (node is root)
            return true;

        return node.upEdges
            .map!(e => e.up)
            .any!(n => linksToRoot(n));
    }

    private bool canBeVisited(const(DgNode) node, const(DgEdge) from)
    {
        foreach (e; node.upEdges)
        {
            if (e is from)
                continue;

            // linksToRoot allows to handle a root in the middle of a graph

            if (!wasVisited(e.up) && linksToRoot(e.up))
                return false;
        }

        return true;
    }

    private bool wasVisited(const(DgNode) node)
    {
        foreach (n; visited)
        {
            if (n is node)
                return true;
        }
        return false;
    }
}

/// Range that traverse a dependency tree upwards.
/// It ensures that each package is traversed after all its dependencies.
struct DependencyDrivenUpNodeRange
{
    import std.range : empty;
    import std.typecons : Flag;

    private static struct TraceUpNode
    {
        Rebindable!(const(DgNode)) node;
        uint edgei;

        bool hasNext() const
        {
            if (node.upEdges.empty)
                return false;
            return edgei < (node.upEdges.length - 1);
        }

        void next()
        {
            edgei++;
        }

        bool valid() const
        {
            return edgei < node.upEdges.length;
        }

        @property const(DgEdge) edge() const
        {
            return node.upEdges[edgei];
        }
    }

    private const(DgNode)[] leaves;
    private TraceUpNode[] traceUp;

    private const(DgNode)[] visited;
    private Rebindable!(const(DgNode)) currNode;
    private Flag!"root" visitRoot;

    this(const(DgNode)[] leaves, Flag!"root" visitRoot)
    {
        this.leaves = leaves;
        this.visitRoot = visitRoot;
        nextLeave();
    }

    @property bool empty() const
    {
        return currNode is null;
    }

    @property const(DgNode) front() const
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

        auto curr = leaves[0];
        if (curr.upEdges.empty && !visitRoot)
            return;

        leaves = leaves[1 .. $];
        traceUp = [TraceUpNode(rebindable(curr), 0)];
        visited ~= curr;
        currNode = curr;
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
            traceUp ~= TraceUpNode(rebindable(above), 0);
            return true;
        }
        return false;
    }

    private bool canBeVisited(const(DgNode) node, const(DgEdge) from)
    {
        if (node.isRoot && !visitRoot)
            return false;

        // A node can be visited if all its dependencies
        // were visited before
        foreach (e; node.downEdges)
        {
            if (e is from)
                continue;

            if (!wasVisited(e.down))
                return false;
        }

        return true;
    }

    private bool wasVisited(const(DgNode) node)
    {
        foreach (n; visited)
        {
            if (n is node)
                return true;
        }
        return false;
    }
}

inout(IgPack)[] getMoreDown(inout(IgPack) pack)
{
    inout(IgPack)[] downs;
    foreach (n; pack.nodes)
    {
        foreach (e; n.downEdges)
            downs ~= e.down;
    }
    return downs;
}

inout(IgPack)[] getMoreUp(inout(IgPack) pack)
{
    inout(IgPack)[] ups;
    ups.reserve(pack.upEdges.length);
    foreach (e; pack.upEdges)
        ups ~= e.up.pack;
    return ups;
}

alias IgDepthFirstTopDownRange(P) = IgDepthFirstRange!(P, getMoreDown);
alias IgDepthFirstBottomUpRange(P) = IgDepthFirstRange!(P, getMoreUp);

struct IgDepthFirstRange(P, alias getMore)
{
    static struct Stage
    {
        P[] packs;
        size_t ind;
    }

    Stage[] stack;
    P[] visited;

    this(P[] starter) @safe
    {
        if (starter.length)
            stack = [Stage(starter, 0)];
        else
            stack = [];
    }

    this(Stage[] stack, P[] visited) @safe
    {
        this.stack = stack;
        this.visited = visited;
    }

    @property bool empty() @safe
    {
        return stack.length == 0;
    }

    @property P front() @safe
    {
        auto stage = stack[$ - 1];
        return stage.packs[stage.ind];
    }

    void popFront() @trusted
    {
        import std.algorithm : canFind;

        auto stage = stack[$ - 1];
        Rebindable!P pack = stage.packs[stage.ind];

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

    void popFrontImpl(P frontPack)
    {
        // getting more on this way if possible
        P[] more = getMore(frontPack);
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

    @property IgDepthFirstRange!(P, getMore) save() @safe
    {
        return IgDepthFirstRange!(P, getMore)(stack.dup, visited.dup!P);
    }
}

// dfmt off
version (unittest):
// dfmt on

import dopamine.dep.source;
import dopamine.profile;

import unit_threaded.assertions;

ResolveConfig mockConfigLinux()
{
    return ResolveConfig(HostInfo(Arch.x86_64, OS.linux), BuildType.debug_, [], OptionSet.init);
}

@("Test general graph utility")
@system
unittest
{
    import std.algorithm : canFind, map;
    import std.array : array;
    import std.typecons : No, Yes;

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    // preferSystem (default): b is a leave
    auto igRootSys = igPrepare(packE.recipe("1.0.0"), config, services);
    igResolve(igRootSys, services);
    auto dgRootSys = dgCreate(igRootSys);

    igRootSys.igCollectLeaves().map!(l => l.name).should ~ ["a"];
    dgRootSys.dgCollectLeaves().map!(l => l.name).should ~ ["a", "b"];

    auto heuristics = Heuristics.preferCache;
    auto igRoot = igPrepare(packE.recipe("1.0.0"), config, services, heuristics);

    igRoot.igTraverseTopDown(Yes.root)
        .map!(p => p.name)
        .should ~ ["a", "b", "c", "d", "e"];

    igRoot.igTraverseTopDown(No.root)
        .map!(p => p.name)
        .should ~ ["a", "b", "c", "d"];

    auto leaves = igCollectLeaves(igRoot);

    igRoot.igTraverseBottomUp(leaves, Yes.root)
        .map!(p => p.name)
        .should ~ ["a", "b", "c", "d", "e"];

    igRoot.igTraverseBottomUp(leaves, No.root)
        .map!(p => p.name)
        .should ~ ["a", "b", "c", "d"];

    igResolve(igRoot, services, heuristics);
    const dgRoot = dgCreate(igRoot);
    auto dgLeaves = dgRoot.dgCollectLeaves();

    // preferCache: only a is a leave
    dgLeaves
        .map!(p => p.name)
        .should ~ ["a"];

    dgRoot.dgTraverseTopDown(Yes.root)
        .map!(p => p.name)
        .should ~ ["a", "b", "c", "d", "e"];

    dgRoot.dgTraverseBottomUp(dgLeaves, Yes.root)
        .map!(p => p.name)
        .should ~ ["a", "b", "c", "d", "e"];
}

@("Test Heuristics.preferSystem")
@system
unittest
{
    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    const heuristics = Heuristics.preferSystem;

    auto dag = resolveDependencies(packE.recipe("1.0.0"), config, services, heuristics);

    auto resolvedVersions = dag.traverseTopDown(Yes.root)
        .map!(n => tuple(n.name.name, n.aver))
        .assocArray;

    resolvedVersions["a"].should == AvailVersion(Semver("1.1.0"), DepLocation.system);
    resolvedVersions["b"].should == AvailVersion(Semver("0.0.3"), DepLocation.system);
    resolvedVersions["c"].should == AvailVersion(Semver("2.0.0"), DepLocation.network);
    resolvedVersions["d"].should == AvailVersion(Semver("1.1.0"), DepLocation.network);
    resolvedVersions["e"].ver.should == "1.0.0";
}

@("Test Heuristics.preferCache")
@system
unittest
{
    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    const heuristics = Heuristics.preferCache;

    auto dag = resolveDependencies(packE.recipe("1.0.0"), config, services, heuristics);

    auto resolvedVersions = dag.traverseTopDown(Yes.root)
        .map!(n => tuple(n.name.name, n.aver))
        .assocArray;

    resolvedVersions["a"].should == AvailVersion(Semver("1.1.0"), DepLocation.cache);
    resolvedVersions["b"].should == AvailVersion(Semver("0.0.1"), DepLocation.cache);
    resolvedVersions["c"].should == AvailVersion(Semver("2.0.0"), DepLocation.network);
    resolvedVersions["d"].should == AvailVersion(Semver("1.1.0"), DepLocation.network);
    resolvedVersions["e"].ver.should == "1.0.0";
}

@("Test Heuristics.preferLocal")
@system
unittest
{
    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    const heuristics = Heuristics.preferLocal;

    auto dag = resolveDependencies(packE.recipe("1.0.0"), config, services, heuristics);

    auto resolvedVersions = dag.traverseTopDown(Yes.root)
        .map!(n => tuple(n.name.name, n.aver))
        .assocArray;

    resolvedVersions["a"].should == AvailVersion(Semver("1.1.0"), DepLocation.cache);
    resolvedVersions["b"].should == AvailVersion(Semver("0.0.3"), DepLocation.system);
    resolvedVersions["c"].should == AvailVersion(Semver("2.0.0"), DepLocation.network);
    resolvedVersions["d"].should == AvailVersion(Semver("1.1.0"), DepLocation.network);
    resolvedVersions["e"].ver.should == "1.0.0";
}

@("Test Heuristics.pickHighest")
@system
unittest
{
    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    const heuristics = Heuristics.pickHighest;

    auto dag = resolveDependencies(packE.recipe("1.0.0"), config, services, heuristics);

    auto resolvedVersions = dag.traverseTopDown(Yes.root)
        .map!(n => tuple(n.name.name, n.aver))
        .assocArray;

    resolvedVersions["a"].should == AvailVersion(Semver("2.0.0"), DepLocation.network);
    resolvedVersions["b"].should == AvailVersion(Semver("0.0.3"), DepLocation.system);
    resolvedVersions["c"].should == AvailVersion(Semver("2.0.0"), DepLocation.network);
    resolvedVersions["d"].should == AvailVersion(Semver("1.1.0"), DepLocation.network);
    resolvedVersions["e"].ver.should == "1.0.0";
}

@("Traverse without deps")
@system
unittest
{
    auto pack = TestPackage("a", [
        TestPackVersion("1.0.1", [], DepLocation.cache)
    ], ["cc"]);
    auto services = buildMockDepServices([]);
    auto config = mockConfigLinux();

    auto dag = resolveDependencies(pack.recipe("1.0.1"), config, services);

    dag.traverseTopDown().shouldBeEmpty();
    dag.traverseBottomUp().shouldBeEmpty();
    dag.traverseTopDown(Yes.root).shouldNotBeEmpty();
    dag.traverseBottomUp(Yes.root).shouldNotBeEmpty();
}

@("Test not resolvable DAG")
@system
unittest
{
    import std.exception : assertThrown;

    auto services = buildMockDepServices(testPackUnresolvable());
    auto config = mockConfigLinux();

    auto recipe = packNotResolvable.recipe("1.0.0");

    assertThrown!UnresolvedDepException(resolveDependencies(recipe, config, services));
}

@("Test DAG (de)serialization through JSON")
@system
unittest
{
    import std.file : write;

    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    auto dag1 = resolveDependencies(packE.recipe("1.0.0"), config, services);

    auto json1 = dag1.toJson();
    auto dag2 = DepGraph.fromJson(json1);
    auto json2 = dag2.toJson();

    json1.toPrettyString().should == json2.toPrettyString();

    // auto dot1 = appender!string();
    // auto dot2 = appender!string();
    // dgToDot(dag1.root, dot1);
    // dgToDot(dag2.root, dot2);

    // dot1.data.should == dot2.data;
}

@("DependencyDrivenDownNodeRange with test graph")
@system
unittest
{
    import std.algorithm;
    import std.typecons;
    import unit_threaded.assertions;

    auto services = buildMockDepServices(testPackBase());
    const config = mockConfigLinux();
    const heuristics = Heuristics.preferSystem;

    auto dag1 = resolveDependencies(packE.recipe("1.0.0"), config, services, heuristics);
    dag1.traverseTopDown(No.root).map!(n => n.name).should == [
        "b", "d", "c", "a"
    ];
    dag1.traverseTopDown(Yes.root).map!(n => n.name)
        .should == ["e", "b", "d", "c", "a"];
}

@("dgTraverseTopDown from middle")
@system
unittest
{
    auto services = buildMockDepServices(testPackBase());
    auto config = mockConfigLinux();

    const heuristics = Heuristics.pickHighest;

    auto dag = resolveDependencies(packE.recipe("1.0.0"), config, services, heuristics);

    const(DgNode) d = dag.traverseTopDown(No.root).find!(n => n.name == "d").front;

    auto resolvedVersions = dgTraverseTopDown(d, Yes.root)
        .map!(n => n.name.name)
        .should == ["d", "c", "a"];
}

@("dgTraverseTopDown with vibe-d:http")
@system
unittest
{
    import std.algorithm;
    import std.array;
    import std.json;
    import std.typecons;
    import unit_threaded.assertions;

    auto jsonLockStr = import("vibe-http-deps.json");
    auto jsonLock = parseJSON(jsonLockStr);
    auto dag = DepGraph.fromJson(jsonLock);

    auto rng = dgTraverseTopDown(dag.root, No.root);
    rng.map!(n => n.name).should == [
        "vibe-d:http",
        "vibe-d:inet",
        "vibe-d:data",
        "vibe-d:textfilter",
        "vibe-d:tls",
        "vibe-d:stream",
        "vibe-d:utils",
        "openssl",
        "openssl-static",
        "vibe-d:crypto",
        "vibe-core",
        "eventcore",
        "taggedalgebraic",
        "stdx-allocator",
        "mir-linux-kernel",
        "diet-ng",
    ];
}

@("dgTraverseTopDown with vibe-d:http from middle")
@system
unittest
{
    import std.algorithm;
    import std.array;
    import std.json;
    import std.typecons;
    import unit_threaded.assertions;

    auto jsonLockStr = import("vibe-http-deps.json");
    auto jsonLock = parseJSON(jsonLockStr);
    auto dag = DepGraph.fromJson(jsonLock);

    auto vibeCore = dgTraverseTopDown(dag.root, No.root).find!(n => n.name == "vibe-core").front;
    dgTraverseTopDown(vibeCore, Yes.root)
        .map!(n => n.name)
        .should == [
            "vibe-core",
            "eventcore",
            "taggedalgebraic",
            "stdx-allocator",
    ];
}

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
                return RecipeDir(new MockRecipe(name, Semver(ver), type, "1", n.deps, tools), testPackDir);
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

    this(TestPackage[string] packs, DepLocation loc)
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

    const(DepSpec)[] depDependencies(const(ResolveConfig) config, string name, Semver ver, string rev = null)
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
