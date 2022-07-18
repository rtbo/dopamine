module dopamine.client.login;

import dopamine.log;
import dopamine.login;

import std.exception;
import std.getopt;
import std.stdio;

int loginMain(string[] args)
{
    string registry;

    // dfmt off
    auto helpInfo = getopt(args,
        "registry|R",    &registry,
    );
    // dfmt on

    if (helpInfo.helpWanted)
        return usage();

    if (args.length < 2)
    {
        logErrorH("missing [TOKEN] argument");
        return usage(1);
    }
    if (args.length > 2)
    {
        logErrorH("too many arguments");
        return usage(1);
    }

    if (hasLoginToken(registry))
    {
        logInfo("Replacing revoked login token");
    }

    writeLoginToken(registry, args[1]);

    return 0;
}

int usage(int code = 0)
{
    if (code == 0)
    {
        logInfo("%s - Dopamine login for remote registry access", info("dop login"));
    }
    logInfo("");
    logInfo("%s", info("Usage"));
    logInfo("    dop login --registry [REGISTRY] [TOKEN]");
    logInfo("");
    logInfo("[REGISTRY] is remote registry on which to log-in");
    logInfo("[TOKEN] is a token that must be obtained from the registry");
    return code;
}
