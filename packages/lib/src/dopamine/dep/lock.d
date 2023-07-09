/// Module to read and write dependency lock files
module dopamine.dep.lock;

package:

import dopamine.dep.resolve;
import dopamine.dep.spec;
import dopamine.dep.service;
import dopamine.recipe : DepSpec, DepProvider, OptionSet, ResolveConfig;
import dopamine.semver;

import std.algorithm;
import std.conv;
import std.exception;
import std.format;
import std.json;
import std.range;
import std.traits;
import std.typecons;

/// Current version of the lock file format
enum currentLockVersion = 1;

/// Serialize a dependency graph to JSON
JSONValue depGraphToJson(DepGraph dag,
    int ver = currentLockVersion) @safe
{
    enforce(ver == 1, "Unsupported lock file format");

    return depGraphToJsonV1(dag);
}

private JSONValue depGraphToJsonV1(DepGraph dag) @safe
{
    JSONValue nodeToJson(const(DgNode) node) @safe
    {
        JSONValue[string] jpack;

        jpack["name"] = node.name;
        jpack["provider"] = node.provider.to!string;
        jpack["version"] = node.ver.toString();

        if (node.aver.location.isSystem)
            jpack["system"] = true;

        if (node.revision)
            jpack["revision"] = node.revision;

        JSONValue[] jdeps;
        foreach (edge; node.downEdges)
        {
            JSONValue[string] jdep;
            jdep["name"] = edge.down.name;
            jdep["provider"] = edge.down.provider.to!string;
            jdep["spec"] = edge.spec.toString();
            jdeps ~= JSONValue(jdep);
        }
        if (jdeps.length)
            jpack["dependencies"] = jdeps;

        if (node.options)
            jpack["options"] = node.options.toJson();

        if (node is dag.root)
            jpack["root"] = true;

        return JSONValue(jpack);
    }

    JSONValue[string] dagDict;

    dagDict["dopamine-lock-version"] = 1;
    dagDict["config"] = dag.config.toJson();

    auto jpacks = dag.traverseTopDown(Yes.root)
        .map!(n => nodeToJson(n))
        .array;
    dagDict["packages"] = JSONValue(jpacks);

    return JSONValue(dagDict);
}

DepGraph jsonToDepGraph(JSONValue json) @safe
{
    enforce(json["dopamine-lock-version"].integer == 1, "Unsupported dependency lock format");

    return jsonToDepGraphV1(json);
}

private T safeJsonGet(T)(JSONValue val, T def = T.init)
{
    static if (is(T == string))
    {
        if (val.type != JSONType.string)
            return def;
        return val.str;
    }
    else static if (is(T == bool))
    {
        if (val.type != JSONType.true_ && val.type != JSONType.false_)
            return def;
        return val.boolean;
    }
    else
        static assert(false, "unimplemented type: " ~ T.stringof);
}

/// Deserialize a dependency DAG from JSON
private DepGraph jsonToDepGraphV1(JSONValue json) @trusted
{
    import std.algorithm : map;
    import std.array : array;

    DgNode nodeFromJson(JSONValue jn)
    {
        auto node = new DgNode;

        auto jnode = jn.objectNoRef;
        node._name = jnode["name"].str;
        node._provider = jnode["provider"].str.to!DepProvider;

        // FIXME: location from service
        auto location = DepLocation.cache;
        if (auto js = "system" in jnode)
            if (js.boolean)
                location = DepLocation.system;
        node._aver = AvailVersion(Semver(jnode["version"].str), location);

        if (auto jr = "revision" in jnode)
            node._revision = jr.str;

        if (auto jo = "options" in jnode)
            node._options = OptionSet.fromJson(*jo);

        return node;
    }

    const config = ResolveConfig.fromJson(json["config"]);

    DgNode root;
    DgNode[string] nodes;

    foreach (jn; json["packages"].arrayNoRef)
    {
        auto node = nodeFromJson(jn);
        const key = packKey(node);
        assert(!(key in nodes));
        nodes[key] = node;
        if (auto r = "root" in jn)
        {
            if (r.boolean)
                root = node;
        }
    }

    foreach (jup; json["packages"].arrayNoRef)
    {
        if (auto jdeps = "dependencies" in jup)
        {
            const upKey = packKey(jup["name"].str, jup["provider"].str.to!DepProvider);
            auto up = nodes[upKey];

            foreach (jdown; jdeps.arrayNoRef)
            {
                const downKey = packKey(jdown["name"].str, jdown["provider"].str.to!DepProvider);
                auto down = nodes[downKey];
                auto edge = new DgEdge;
                edge._spec = VersionSpec(jdown["spec"].str);
                edge._up = up;
                up._downEdges ~= edge;
                edge._down = down;
                down._upEdges ~= edge;
                enforce(
                    edge._spec.matchVersion(down.ver),
                    new Exception(
                        format!"Corrupted lock file: %s dependency specification %s %s doesn't match version %s "(
                        up.name, down.name, edge._spec.toString(), down.ver
                    )
                ));
            }
        }
    }

    return DepGraph(root, config);
}
