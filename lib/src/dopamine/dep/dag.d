/// Dependency Directed Acyclic Graph
///
/// This a kind of hybrid graph with the following abstractions:
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
            verBumpScore = lowScore + 1; // avoid tie if we have system one version above the last cache
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
            AvailVersion(Semver("3.0.0"), DepLocation.cache));
    assert(heuristicsHighest.chooseVersion(compatibleVersions2) ==
            AvailVersion(Semver("3.0.0"), DepLocation.network));
    assert(heuristicsHighest.chooseVersion(compatibleVersions3) ==
            AvailVersion(Semver("3.0.0"), DepLocation.network));
}

struct DepDAG
{
    DagPack root;

    // static DepDAG prepare(Recipe recipe, Profile profile, DepService service,
    //     Heuristics heuristics = Heuristics.init) @system
    // {
    //     import std.algorithm : canFind, filter, sort, uniq;
    //     import std.array : array;

    //     DagPack[string] packs;

    //     DagPack prepareDagPack(DepSpec dep)
    //     {
    //         auto avs = service.packAvailVersions(dep.name)
    //             .filter!(av => dep.spec.matchVersion(av.ver))
    //             .filter!(av => heuristics.allow(dep.name, av))
    //             .array;

    //         DagPack pack;
    //         if (auto p = dep.name in packs)
    //             pack = *p;

    //         if (pack)
    //         {
    //             avs ~= pack.allVersions;
    //         }
    //         else
    //         {
    //             pack = new DagPack(dep.name);
    //             packs[dep.name] = pack;
    //         }

    //         pack.allVersions = sort(avs).uniq().array;
    //         return pack;
    //     }

    //     DepDAG dag;
    //     dag.root = new DagPack(recipe.name);
    //     dag.root.allVersions = [AvailVersion(recipe.ver, DepLocation.cache)];

    //     DagNode[] visited;

    //     void doPackVersion(DagPack pack, AvailVersion aver)
    //     {
    //         auto node = pack.getOrCreateNode(aver.ver);
    //         if (visited.canFind(node))
    //         {
    //             return;
    //         }

    //         visited ~= node;

    //         const(DepSpec)[] deps;
    //         if (aver.location != DepLocation.system)
    //         {
    //             if (pack is dag.root)
    //             {
    //                 deps = recipe.dependencies(profile);
    //             }
    //             else
    //             {
    //                 auto rec = service.packRecipe(pack.name, aver.ver);
    //                 node.revision = rec.revision;
    //                 deps = rec.dependencies(profile);
    //             }
    //         }

    //         foreach (dep; deps)
    //         {
    //             auto dp = prepareDagPack(dep);
    //             DagEdge.create(node, dp, dep.spec);

    //             const dv = heuristics.chooseVersion(dp.allVersions);
    //             doPackVersion(dp, dv);
    //         }
    //     }

    //     return dag;
    // }

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
    package DagNode getOrCreateNode(const(Semver) ver) @safe
    {
        foreach (n; nodes)
        {
            if (n.ver == ver)
                return n;
        }
        auto node = new DagNode(this, ver);
        nodes ~= node;
        return node;
    }

    /// Get existing node that match with [ver], or null
    package DagNode getNode(const(Semver) ver) @safe
    {
        foreach (n; nodes)
        {
            if (n.ver == ver)
                return n;
        }
        return null;
    }
}

/// Dependency DAG node: represent a package with a specific version
/// and a set of sub-dependencies.
class DagNode
{
    /// The package owner of this version node
    DagPack pack;

    /// The package version
    Semver ver;

    /// The package location
    DepLocation location;

    /// The package revision
    string revision;

    /// The edges going to dependencies of this package
    DagEdge[] downEdges;

    /// The languages of this node and all dependencies
    /// This is generally fetched after resolution
    Lang[] langs;

    /// User data
    Object userData;

    this(DagPack pack, Semver ver) @safe
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
class DagEdge
{
    DagNode up;
    DagPack down;
    VersionSpec spec;

    /// Create a dependency edge between a package version and another package
    static DagEdge create(DagNode up, DagPack down, VersionSpec spec) @safe
    {
        auto edge = new DagEdge;

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
