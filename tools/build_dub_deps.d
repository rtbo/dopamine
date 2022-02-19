module build_dub_deps;

import std.getopt;
import std.json;
import std.process;
import std.stdio;

struct Pack
{
    string name;
    string ver;
    string config;

    @property string dubId()
    {
        assert(name);
        if (ver)
            return name ~ "@" ~ ver;
        else
            return name;
    }
}

struct DubConfig
{
    string exe;
    string compiler;
    string arch;
    bool release;

    string[] makeCmd(string name, Pack pack)
    {
        auto cmd = [
            exe, name, pack.dubId
        ];
        if (pack.config)
            cmd ~= ["--config", pack.config];

        if (compiler)
            cmd ~= ["--compiler", compiler];

        if (arch)
            cmd ~= ["--arch", arch];

        if (release)
            cmd ~= ["--build", "release"];
        else
            cmd ~= ["--build", "debug"];

        return cmd;
    }
}

int main(string[] args)
{
    Pack pack;

    DubConfig dub;
    dub.exe = "dub";

    auto helpInfo = getopt(args,
        "pack", "Name of the package to fetch and build", &pack.name,
        "ver", "Version of the package to fetch and build", &pack.ver,
        "config", "Specificy a DUB configuration", &pack.config,
        "dub", "Specify a DUB executable", &dub.exe,
        "compiler", "D compiler to be used", &dub.compiler,
        "arch", "Architecture to target", &dub.arch,
        "release", "Activate release build (default to Debug otherwise)", &dub.release,
    );

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter(
            "Build a DUB package and all its sub-dependencies",
            helpInfo.options
        );
    }

    if (!pack.name)
    {
        stderr.writeln("--pack argument is mandatory");
        return 1;
    }

    const describeCmd = dub.makeCmd("describe", pack);

    writeln("running ", escapeShellCommand(describeCmd));
    auto describe = execute(describeCmd);

    if (describe.status != 0)
    {
        stderr.writeln("describe command returned ", describe.status);
        stderr.writeln(describe.output);
        return describe.status;
    }

    auto json = parseJSON(describe.output);

    foreach (jp; json["packages"].array)
    {
        if (!jp["active"].boolean)
            continue;

        const targetType = jp["targetType"].str;
        if (targetType == "none" || targetType == "sourceLibrary")
            continue;

        Pack p;
        p.name = jp["name"].str;
        p.ver = jp["version"].str;
        p.config = jp["configuration"].str;

        const res = buildDubPackage(p, dub);

        if (res)
            return res;
    }

    return 0;
}

int buildDubPackage(Pack pack, DubConfig dub)
{
    const buildCmd = dub.makeCmd("build", pack);
    writeln("running ", escapeShellCommand(buildCmd));
    auto res = execute(buildCmd);
    if (res.status != 0)
    {
        stderr.writeln(res.output);
    }
    return res.status;
}
