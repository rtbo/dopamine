module dopamine.client.app;

import dopamine.client.build;
import dopamine.client.install;
import dopamine.client.login;
import dopamine.client.pack;
import dopamine.client.profile;
import dopamine.client.publish;
import dopamine.client.source;
import dopamine.client.upload;

import bindbc.lua;

import std.algorithm;
import std.getopt;
import std.file;
import std.format;
import std.process;
import std.stdio;

int main(string[] args)
{
    import dopamine.log : error, info, logError, logInfo;
    import dopamine.recipe : initLua;
    import dopamine.state : StateNotReachedException;

    initLua();

    const commandHandlers = [
        "build" : &buildMain, "install" : &installMain, "login" : &loginMain,
        "package" : &packageMain, "profile" : &profileMain,
        "publish" : &publishMain, "source" : &sourceMain, "upload" : &uploadMain,
    ];

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

    auto helpInfo = getopt(globalArgs, "change-dir|C", &changeDir,);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("The Dopamine package manager", helpInfo.options);
        return 0;
    }
    if (changeDir.length)
    {
        logInfo("changing current directory to %s", info(changeDir));
        chdir(changeDir);
    }

    args = globalArgs ~ leftover;

    const command = args.length > 1 ? args[1] : null;

    auto handler = command in commandHandlers;
    if (!handler)
    {
        logError("unknown command: %s", error(command));
        return 1;
    }

    // merge command name
    args[0] = format("dop-%s", command);
    args = args.remove(1);

    try
    {
        return (*handler)(args);
    }
    catch (StateNotReachedException)
    {
        // Error already logged out.
        return 1;
    }
    catch (Exception ex)
    {
        logError("%s: %s", error("Error"), ex.msg);
        return 1;
    }
}
