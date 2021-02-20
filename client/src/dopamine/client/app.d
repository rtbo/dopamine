module dopamine.client.app;

import dopamine.client.build;
import dopamine.client.cache;
import dopamine.client.deplock;
import dopamine.client.login;
import dopamine.client.pack;
import dopamine.client.profile;
import dopamine.client.publish;
import dopamine.client.source;
import dopamine.log;

import std.getopt;
import std.file;
import std.format;

// TODO version from meson
enum dopVersion = "0.1.0-alpha";

alias CommandFunc = int function(string[] args);

struct Command
{
    string name;
    CommandFunc func;
    string desc;
}

int main(string[] args)
{
    import std.algorithm : canFind, find, map, remove;
    import std.array : array;
    import dopamine.lua : initLua;

    initLua();

    const commands = [
        Command("login", &loginMain, "Register login credientials"),
        Command("profile", &profileMain, "Set compilation profile for the current package"),
        Command("deplock", &depLockMain, "Lock dependencies"),
        Command("source", &sourceMain, "Download package source"),
        Command("build", &buildMain, "Build package"),
        Command("package", &packageMain, "Create package from build"),
        Command("cache", &cacheMain, "Add package to local cache"),
        Command("publish", &publishMain, "Publish package to repository"),
    ];
    // TODO: missing commands
    // - config: specify build options, install path etc.
    // - upload: upload a build on a remote repo

    const commandNames = commands.map!(c => c.name).array;

    // processing a few global args here

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

    auto helpInfo = getopt(globalArgs, "change-dir|C",
            "Change current directory before running command", &changeDir, "verbose|v",
            "Enable verbose mode", &verbose, "version", "Show dop version and exits", &showVer);

    if (helpInfo.helpWanted)
    {
        return showHelp(helpInfo, commands);
    }
    if (showVer)
    {
        logInfo("%s", info(dopVersion));
        return 0;
    }
    if (verbose)
    {
        minLogLevel = LogLevel.verbose;
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

    // merge command name
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
