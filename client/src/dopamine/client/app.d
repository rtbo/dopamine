module dopamine.client.app;

import dopamine.client.build;
import std.algorithm;
import std.process;
import std.stdio;

import bindbc.lua;

int main(string[] args)
{

    version (LUA_53_DYNAMIC) {
        LuaSupport ret = loadLua();

        if(ret != luaSupport) {
            if(ret == luaSupport.noLibrary) {
                throw new Exception("could not find lua library");
            }
            else if(luaSupport.badLibrary) {
                throw new Exception("could not find the right lua library");
            }
        }
    }

    auto commandHandlers = [
        "build": &buildMain,
    ];

    string command = "build";

    if (args.length > 1 && args[1][0] != '-')
    {
        command = args[1];
        args = args.remove(1);
    }

    auto handler = command in commandHandlers;
    if (handler) {
        return (*handler)(args);
    }

    stderr.writeln("unknown command: ", command);
    return 1;
}
