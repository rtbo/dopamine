module dopamine.client.app;

import dopamine.conf;
import dopamine.log;

import std.getopt;
import std.stdio;

alias CommandFunc = int function(string[] args);

struct Command
{
    string name;
    CommandFunc func;
    string desc;
}

int main(string[] args)
{
    bool showVer;

    auto helpInfo = getopt(args,
        "version", "Show dopamine version", &showVer
    );

    if (helpInfo.helpWanted) {
        return showHelp(helpInfo, []);
    }

    if (showVer) {
        logInfo("%s", info(dopamineVersion));
        return 0;
    }

    return 0;
}

int showHelp(GetoptResult helpInfo, in Command[] commands)
{
    import std.algorithm : map, max, maxElement;

    logInfo("%s - Dopamine package manager client", info("dop"));
    logInfo("");
    logInfo("%s", info("Usage"));
    logInfo("    dop [global options] command [command options]");
    logInfo("");

    logInfo("%s", info("Global options"));

    size_t ls, ll;
    bool hasRequired;
    foreach (opt; helpInfo.options)
    {
        ls = max(ls, opt.optShort.length);
        ll = max(ll, opt.optLong.length);

        hasRequired = hasRequired || opt.required;
    }

    string re = " Required: ";

    foreach (opt; helpInfo.options)
    {
        logInfo("    %*s %*s%*s %s", ls, opt.optShort, ll, opt.optLong,
                hasRequired ? re.length : 1, opt.required ? re : " ", opt.help);
    }

    logInfo("");
    logInfo("%s", info("Commands:"));
    const maxName = commands.map!(cmd => cmd.name.length).maxElement;
    foreach (cmd; commands)
    {
        logInfo("    %*s  %s", maxName, cmd.name, cmd.desc);
    }
    logInfo("For individual command help, type %s", info("dop [command] --help"));

    return 0;
}
