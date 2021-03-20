module meson_dub_deps;

import std.exception;
import std.format;
import std.getopt;
import std.process;
import std.meta;

string dub = "dub";
string dc;

// dfmt off
// package, option, default version
alias deps = AliasSeq!(
    "dini", "dini", "2.0.0",
    "exceptionhandling", "eh", "1.0.0",
);
// dfmt on

string getoptCode()
{
    string code;
    code ~= `auto helpInfo = getopt(args, "dub", "Dub executable", &dub, "dc", "The D compiler", &dc, `;
    static foreach (i; 0 .. deps.length / 3)
    {
        code ~= format(`"%s", "override for %s version", &depVers[%s], `,
                deps[i * 3 + 1], deps[i * 3], i);
    }
    code ~= ");";
    return code;
}

int main(string[] args)
{
    string[] depVers;
    static foreach (i; 0 .. deps.length / 3)
    {
        depVers ~= deps[i * 3 + 2];
    }

    mixin(getoptCode());

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("Prepare DUB dependencies.", helpInfo.options);
        return 0;
    }

    if (!dc)
    {
        dc = environment.get("DC", null);
    }

    static foreach (i; 0 .. deps.length / 3)
    {
        ensureDubPkg(deps[i * 3], depVers[i]);
    }

    return 0;
}

void ensureDubPkg(string name, string ver)
{
    const spec = format("%s@%s", name, ver);

    auto fetch = spawnProcess([dub, "fetch", spec]);
    enforce(wait(fetch) == 0, "dub failed to fetch " ~ spec);

    auto buildcmd = [dub, "build", "--yes", spec];
    if (dc)
    {
        buildcmd ~= "--compiler=" ~ dc;
    }
    auto build = spawnProcess(buildcmd);
    enforce(wait(build) == 0, "dub failed to build " ~ spec);
}
