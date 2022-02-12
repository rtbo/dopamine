/// Module to read and write dependency lock files
module dopamine.dep.lock;

import dopamine.dep.dag;
import dopamine.dep.service;
import dopamine.dep.spec;
import dopamine.semver;

import std.conv;
import std.exception;
import std.json;
import std.range;
import std.traits;
import std.typecons;

/// Current version of the lock file format
enum lockVer = 1;

/// Serialize a dependency DAG to JSON
JSONValue writeDagLock(ref DepDAG dag,
    Flag!"emitAllVersions" emitAllVersions = Yes.emitAllVersions,
    int ver = lockVer)
in (emitAllVersions || dag.resolved)
{
    enforce(ver == 1, "Unsupported lock file format");

    return writeDagV1(dag, emitAllVersions);
}

private JSONValue writeDagV1(ref DepDAG dag,
    Flag!"emitAllVersions" emitAllVersions)
{
    JSONValue[string] dagDict;

    dagDict["dopamine-lock-ver"] = 1;

    JSONValue[string] heur;
    heur["mode"] = dag.heuristics.mode.to!string;
    heur["system"] = dag.heuristics.system.to!string;
    heur["systemList"] = JSONValue(dag.heuristics.systemList);
    dagDict["heuristics"] = heur;

    JSONValue[] packs;
    foreach (pack; dag.traverseTopDown(Yes.root))
    {
        JSONValue[string] packDict;

        packDict["name"] = pack.name;

        JSONValue[] vers;

        foreach (aver; pack.allVersions)
        {
            JSONValue[string] verDict;

            verDict["version"] = aver.ver.to!string();
            verDict["location"] = aver.location.to!string();

            auto n = pack.getNode(aver);

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

                if (n.langs.length)
                {
                    import dopamine.profile : strFromLangs;

                    verDict["langs"] = n.langs.strFromLangs();
                }
                JSONValue[] deps;
                foreach (e; n.downEdges)
                {
                    string[string] depDict;
                    depDict["name"] = e.down.name;
                    depDict["spec"] = e.spec.to!string();
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

/// Deserialize a dependency DAG from JSON
DepDAG readDagLock(JSONValue value)
{
    import std.algorithm : map;
    import std.array : array;

    enforce(value["dopamine-lock-ver"].integer == 1, "Unsupported dependency lock format");

    static struct Dep
    {
        string pack;
        AvailVersion aver;
        string down;
        VersionSpec spec;
    }

    Heuristics heuristics;
    JSONValue jheur = value["heuristics"];
    heuristics.mode = jheur["mode"].str.to!(Heuristics.Mode);
    heuristics.system = jheur["system"].str.to!(Heuristics.System);
    heuristics.systemList = jheur["system-list"].array.map!(jv => jv.str).array;

    DagPack root;
    DagPack[string] packs;
    Dep[] deps;

    foreach (jpack; value["packages"].array)
    {
        DagPack p = new DagPack(jpack["name"].str);

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

                if (const(JSONValue)* jrev = "revision" in jver)
                {
                    node.revision = jrev.str;
                }
                if (const(JSONValue)* jlangs = "langs" in jver)
                {
                    import dopamine.profile : fromConfig, strToLang;

                    node.langs = jlangs.array
                        .map!(jv => jv.str)
                        .map!(ls => strToLang(ls))
                        .array;
                }
            }
            if (const(JSONValue)* jdeps = "dependencies" in jver)
            {
                foreach (jdep; jdeps.array)
                {
                    Dep dep;
                    dep.pack = p.name;
                    dep.aver = aver;
                    dep.down = jdep["down"].str;
                    dep.spec = VersionSpec(jdep["spec"].str);
                    deps ~= dep;
                }
            }
        }

        p.allVersions = allVers;
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
        auto down = packs[d.down];
        DagEdge.create(up, down, d.spec);
    }

    return DepDAG(root, heuristics);
}
