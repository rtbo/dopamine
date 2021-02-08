module dopamine.client.app;

import dopamine.client.build;
import dopamine.client.cache;
import dopamine.client.deplock;
import dopamine.client.login;
import dopamine.client.profile;
import dopamine.client.publish;
import dopamine.client.source;
import dopamine.log;

import std.getopt;
import std.file;
import std.format;

int main(string[] args)
{
    import std.algorithm : canFind, remove;
    import dopamine.lua : initLua;

    initLua();

    const commandHandlers = [
        "login" : &loginMain, "profile" : &profileMain, "deplock" : &depLockMain,
        "source" : &sourceMain, "build" : &buildMain, "cache" : &cacheMain,
        "publish": &publishMain,
    ];
    // TODO: missing commands
    // - config: specify build options, install path etc.
    // - package: stage built data in a directory (typically install operation)
    // - publish: publish a recipe on a remote repo
    // - upload: upload a build on a remote repo

    const commandNames = commandHandlers.keys;

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

    auto helpInfo = getopt(globalArgs, "change-dir|C", &changeDir, "verbose|v", &verbose);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("The Dopamine package manager", helpInfo.options);
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

    const command = args.length > 1 ? args[1] : null;

    if (!command)
    {
        logError("%s: no command specified", error("Error"));
        return 1;
    }

    auto handler = command in commandHandlers;
    if (!handler)
    {
        logError("%s: unknown command: %s", error("Error"), info(command));
        return 1;
    }

    // merge command name
    args[0] = format("dop-%s", command);
    args = args.remove(1);

    try
    {
        return (*handler)(args);
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
