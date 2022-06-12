module dopamine.client.app;

import dopamine.client.build;
import dopamine.client.login;
import dopamine.client.profile;
import dopamine.client.publish;
import dopamine.client.resolve;
import dopamine.client.source;
import dopamine.client.stage;

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

version(DopClientMain)
int main(string[] args)
{
    import std.algorithm : canFind, find, map, remove;
    import std.array : array;
    import std.file : chdir;
    import std.format : format;

    const commands = [
        Command("login", &loginMain, "Register login credientials"),
        Command("profile", &profileMain, "Manage compilation profile"),
        Command("resolve", &resolveMain, "Resolve and lock dependencies versions"),
        Command("source", &sourceMain, "Download and prepare the source code"),
        Command("build", &buildMain, "Build the package"),
        Command("stage", &stageMain, "Stage the package"),
        Command("publish", &publishMain, "Publish the package"),
    ];
    const commandNames = commands.map!(c => c.name).array;

    string[] globalArgs = args;
    string[] leftover;
    for (size_t i = 1; i < args.length; i++)
    {
        if (commandNames.canFind(args[i]))
        {
            globalArgs = args[0 .. i];
            leftover = args[i .. $];
            break;
        }
    }

    string changeDir;
    bool verbose;
    bool showVer;

    auto helpInfo = getopt(globalArgs,
        "change-dir|C", "Change current directory before running command", &changeDir,
        "verbose|v", "Enable verbose mode", &verbose,
        "version", "Show dopamine version", &showVer
    );

    if (helpInfo.helpWanted)
    {
        return showHelp(helpInfo, args.length > 0 ? args[0] : "dop", commands);
    }

    if (verbose)
    {
        minLogLevel = LogLevel.verbose;
    }
    if (showVer)
    {
        // verbose version info?
        logInfo("%s", info(DOP_VERSION));
        return 0;
    }
    if (changeDir.length)
    {
        logInfo("changing current directory to %s", info(changeDir));
        chdir(changeDir);
    }

    args = globalArgs ~ leftover;

    const cmdName = args.length > 1 ? args[1] : null;

    if (!cmdName)
    {
        logError("%s: no command specified", error("Error"));
        return 1;
    }

    auto cmd = commands.find!(cmd => cmd.name == cmdName);
    if (cmd.length == 0)
    {
        logError("%s: unknown command: %s", error("Error"), info(cmdName));
        return 1;
    }

    // prepare command line for the actual driver
    args[0] = format("dop-%s", cmdName);
    args = args.remove(1);

    try
    {
        return cmd[0].func(args);
    }
    catch (FormatLogException ex)
    {
        ex.log();
    }
    catch (Exception ex)
    {
        logError("%s: %s", error("Error"), ex.msg);
    }
    return 1;
}

int showHelp(GetoptResult helpInfo, string exeName, in Command[] commands)
{
    import std.algorithm : map, max, maxElement;

    logInfo("%s - Dopamine package manager client", info("dop"));
    logInfo("");
    logInfo("%s", info("Usage"));
    logInfo("    %s [global options] command [command options]", exeName);
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
    const maxName = commands.length ? commands.map!(cmd => cmd.name.length).maxElement : 0;
    foreach (cmd; commands)
    {
        logInfo("    %*s  %s", maxName, cmd.name, cmd.desc);
    }
    logInfo("");
    logInfo("For individual command help, type %s", info("dop [command] --help"));

    return 0;
}
