module meson_dub_deps;

import std.exception;
import std.format;
import std.getopt;
import std.process;

string dub = "dub";
string diniVer = "2.0.0";
string utVer = "1.0.11";
string dc;

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

int main(string[] args)
{
    auto helpInfo = getopt(args, "dub", &dub, "dini", &diniVer,
            "unit-threaded", &utVer, "dc", &dc);
    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("Some information about the program.", helpInfo.options);
        return 0;
    }

    if (!dc)
    {
        dc = environment.get("DC", null);
    }

    ensureDubPkg("dini", diniVer);
    ensureDubPkg("unit-threaded", utVer);
    ensureDubPkg("unit-threaded:runner", utVer);
    ensureDubPkg("unit-threaded:exception", utVer);
    ensureDubPkg("unit-threaded:assertions", utVer);
    ensureDubPkg("unit-threaded:integration", utVer);
    ensureDubPkg("unit-threaded:property", utVer);
    ensureDubPkg("unit-threaded:from", utVer);
    ensureDubPkg("unit-threaded:mocks", utVer);

    return 0;
}
