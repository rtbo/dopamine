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
        JSONValue[string] jnode;

        jnode["name"] = node.name;
        jnode["provider"] = node.provider.to!string;
        jnode["version"] = node.ver.toString();

        if (node.aver.location.isSystem)
            jnode["system"] = true;

        if (node.revision)
            jnode["revision"] = node.revision;

        JSONValue[] jdeps;
        foreach (dep; node.deps)
            jdeps ~= dep.toJson();
        if (jdeps.length)
            jnode["dependencies"] = jdeps;

        if (node.options)
            jnode["options"] = node.options.toJson();

        return JSONValue(jnode);
    }

    JSONValue edgeToJson(const(DgEdge) edge) @safe
    {
        JSONValue[string] jedge;

        jedge["up"] = [
            "name": edge.up.name,
            "provider": edge.up.provider.to!string,
        ];
        jedge["down"] = [
            "name": edge.down.name,
            "provider": edge.down.provider.to!string,
        ];
        jedge["spec"] = edge.spec.toString();

        return JSONValue(jedge);
    }

    JSONValue[string] dagDict;

    dagDict["dopamine-lock-version"] = 1;

    dagDict["config"] = dag.config.toJson();

    JSONValue[] jnodes;
    JSONValue[] jedges;

    foreach (const(DgNode) node; dag.traverseTopDown(Yes.root))
    {
        auto jnode = nodeToJson(node);

        if (node is dag.root)
            dagDict["root"] = jnode;
        else
            jnodes ~= jnode;

        node.downEdges.each!(e => jedges ~= edgeToJson(e));
    }

    dagDict["nodes"] = jnodes;
    dagDict["edges"] = jedges;

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

        if (auto jd = "dependencies" in jnode)
        {
            foreach (jdep; jd.arrayNoRef)
                node._deps ~= DepSpec.fromJson(jdep);
        }

        if (auto jo = "options" in jnode)
            node._options = OptionSet.fromJson(*jo);

        return node;
    }

    const config = ResolveConfig.fromJson(json["config"]);

    DgNode[string] nodes;

    auto root = nodeFromJson(json["root"]);
    nodes[packKey(root)] = root;

    foreach (jn; json["nodes"].arrayNoRef)
    {
        auto node = nodeFromJson(jn);
        const key = packKey(node);
        assert(!(key in nodes));
        nodes[key] = node;
    }

    foreach (je; json["edges"].arrayNoRef)
    {
        auto edge = new DgEdge;
        auto jup = je["up"];
        auto jdown = je["down"];
        const upKey = packKey(jup["name"].str, jup["provider"].str.to!DepProvider);
        const downKey = packKey(jdown["name"].str, jdown["provider"].str.to!DepProvider);
        const spec = VersionSpec(je["spec"].str);

        auto up = nodes[upKey];
        auto down = nodes[downKey];

        edge._up = up;
        up._downEdges ~= edge;
        edge._down = down;
        down._upEdges ~= edge;
        edge._spec = spec;
    }

    return DepGraph(root, config);
}
