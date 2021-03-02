module test.main;

import test.util : testPath;

import std.exception : enforce;
import std.process : execute;
import std.file;


shared static this()
{
    import dopamine.log : minLogLevel, LogLevel;

    enforce(execute(["dub", "add-path", testPath("pkgs")]).status == 0);
    printEtcLdSoConf();
}

shared static ~this()
{
    enforce(execute(["dub", "remove-path", testPath("pkgs")]).status == 0);
    printEtcLdSoConf();
}

void printEtcLdSoConf()
{
    import std.stdio : writefln;

    const conf = "/etc/ld.so.conf";
    const confd = "/etc/ld.so.conf.d";

    void catFile(string fn)
    {
        if (fn.exists && fn.isFile)
        {
            const content = cast(const(char)[])read(fn);
            writefln("%s:", fn);
            writefln("%s", content);
        }
        else
        {
            writefln("%s: No such file", fn);
        }
    }

    void catDir(string dn)
    {
        foreach(e; dirEntries(dn, SpanMode.breadth))
        {
            if (e.isDir) catDir(e.name);
            else catFile(e.name);
        }
    }

    catFile(conf);
    catDir(confd);
}


int main()
{
    return 0;
}
