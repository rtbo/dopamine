module dopamine.client.app;

import dopamine.client.build;
import dopamine.client.install;
import dopamine.client.login;
import dopamine.client.pack;
import dopamine.client.profile;
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
    import dopamine.recipe : initLua;

    initLua();

    const commandHandlers = [
        "build" : &buildMain, "install" : &installMain, "login" : &loginMain,
        "package" : &packageMain, "profile" : &profileMain,
        "source" : &sourceMain, "upload" : &uploadMain,
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
        writeln("changing current directory to ", changeDir);
        chdir(changeDir);
    }

    args = globalArgs ~ leftover;

    const command = args.length > 1 ? args[1] : null;

    auto handler = command in commandHandlers;
    if (!handler)
    {
        stderr.writeln("unknown command: ", command);
        return 1;
    }

    // remove command name
    args = args.remove(1);

    try
    {
        return (*handler)(args);
    }
    catch (Exception ex)
    {
        stderr.writeln(format("Error occured during %s execution:\n%s", command, ex.msg));
        return 1;
    }
}
