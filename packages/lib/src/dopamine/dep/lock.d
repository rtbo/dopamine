/// Module to read and write dependency lock files
module dopamine.dep.lock;

package:

import dopamine.dep.dag;
import dopamine.dep.service;
import dopamine.dep.spec;
import dopamine.recipe : DepSpec, OptionSet;
import dopamine.semver;

import std.conv;
import std.exception;
import std.format;
import std.json;
import std.range;
import std.traits;
import std.typecons;

/// Current version of the lock file format
enum lockVer = 1;

/// Serialize a dependency DAG to JSON
JSONValue dagToJson(ref DepDAG dag,
    Flag!"emitAllVersions" emitAllVersions = Yes.emitAllVersions,
    int ver = lockVer) @safe
in (emitAllVersions || dag.resolved)
{
    enforce(ver == 1, "Unsupported lock file format");

    return dagToJsonV1(dag, emitAllVersions);
}

private JSONValue dagToJsonV1(ref DepDAG dag,
    Flag!"emitAllVersions" emitAllVersions) @safe
{
    JSONValue[string] dagDict;

    dagDict["dopamine-lock-version"] = 1;

    JSONValue[string] heur;
    heur["mode"] = dag.heuristics.mode.to!string;
    heur["system"] = dag.heuristics.system.to!string;
    heur["system-list"] = JSONValue(dag.heuristics.systemList);
    dagDict["heuristics"] = heur;

    JSONValue[] packs;
    foreach (pack; dag.traverseTopDown(Yes.root))
    {
        JSONValue[string] packDict;

        packDict["name"] = pack.name;
        packDict["dub"] = pack.dub;

        JSONValue[] vers;

        foreach (aver; pack.allVersions)
        {
            JSONValue[string] verDict;

            verDict["version"] = aver.ver.to!string();
            verDict["location"] = aver.location.to!string();

            auto n = pack.getNode(aver);

            if (n)
            {
                if (n.options.length)
                {
                    verDict["options"] = JSONValue(n.options.toJSON());
                }
                if (n.optionConflicts.length)
                {
                    verDict["optionConflicts"] = JSONValue(n.optionConflicts);
                }
            }

            string status;

            if (n is null && !emitAllVersions)
                continue;
            if (n && n is pack.resolvedNode)
            {
                status = "resolved";
            }
            else if (n)
            {
                status = "compatible";
            }
            else
            {
                status = "removed";
            }
            verDict["status"] = status;

            if (n !is null)
            {
                if (n.revision)
                {
                    verDict["revision"] = n.revision;
                }

                JSONValue[] deps;
                foreach (e; n.downEdges)
                {
                    deps ~= JSONValue([
                        "name": e.down.name,
                        "spec": e.spec.to!string(),
                    ]);
                }
                verDict["dependencies"] = deps;
            }
            vers ~= JSONValue(verDict);
        }
        packDict["versions"] = vers;
        packs ~= JSONValue(packDict);
    }
    dagDict["packages"] = packs;

    return JSONValue(dagDict);
}

DepDAG jsonToDag(JSONValue json) @safe
{
    enforce(json["dopamine-lock-version"].integer == 1, "Unsupported dependency lock format");

    return jsonToDagV1(json);
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
private DepDAG jsonToDagV1(JSONValue json) @trusted
{
    import std.algorithm : map;
    import std.array : array;

    static struct Dep
    {
        string pack;
        AvailVersion aver;
        string down;
        VersionSpec spec;
    }

    Heuristics heuristics;
    JSONValue jheur = json["heuristics"];
    heuristics.mode = jheur["mode"].str.to!(Heuristics.Mode);
    heuristics.system = jheur["system"].str.to!(Heuristics.System);
    heuristics.systemList = jheur["system-list"].array.map!(jv => jv.str).array;

    DagPack root;
    DagPack[string] packs;
    Dep[] deps;

    foreach (jpack; json["packages"].array)
    {
        const name = jpack["name"].str;
        const dub = safeJsonGet!bool(jpack["dub"]);

        DagPack p = new DagPack(name, dub);

        AvailVersion[] allVers;
        DagNode[] nodes;

        foreach (jver; jpack["versions"].array)
        {
            AvailVersion aver;
            aver.ver = Semver(jver["version"].str);
            aver.location = jver["location"].str.to!DepLocation;

            allVers ~= aver;

            const status = jver["status"].str;

            if (status == "resolved" || status == "compatible")
            {
                DagNode node = new DagNode(p, aver);
                nodes ~= node;
                if (status == "resolved")
                {
                    p.resolvedNode = node;
                }

                if (const(JSONValue)* jrev = "revision" in jver)
                {
                    node.revision = jrev.str;
                }

                if (const(JSONValue)* jopts = "options" in jver)
                {
                    node.options = OptionSet(jopts.objectNoRef);
                }
                if (const(JSONValue)* jconflicts = "optionConflicts" in jver)
                {
                    foreach (jc; jconflicts.arrayNoRef)
                        node.optionConflicts ~= jc.str;
                }
            }
            if (const(JSONValue)* jdeps = "dependencies" in jver)
            {
                foreach (jdep; jdeps.array)
                {
                    Dep dep;
                    dep.pack = p.name;
                    dep.aver = aver;
                    dep.down = jdep["name"].str;
                    dep.spec = VersionSpec(jdep["spec"].str);
                    deps ~= dep;
                }
            }
        }

        p._allVersions = allVers;
        p.nodes = nodes;
        packs[p.name] = p;

        if (root is null)
        {
            root = p;
        }
    }

    foreach (d; deps)
    {
        auto up = packs[d.pack].getNode(d.aver);
        enforce(up, format("Can't find node %s in package %s", d.aver, d.pack));
        auto down = packs[d.down];
        DagEdge.create(up, down, d.spec);
    }

    return DepDAG(root, heuristics);
}
