module dopamine.client.login;

import dopamine.log;
import dopamine.login;

import std.exception;
import std.getopt;
import std.stdio;

int loginMain(string[] args)
{
    import std.algorithm : find;

    auto help = args.find!(a => a == "-h" || a == "--help");
    if (help.length)
    {
        return usage();
    }

    if (args.length != 2)
    {
        logError("%s: %s must be called with a %s as argument", error("Error"), info("dop login"), info(
                "key"));
        return usage(1);
    }

    const key = args[1];
    const loginKey = decodeLoginKey(key);

    if (isLoggedIn())
    {
        const current = readLoginKey();
        logInfo("%s: Replacing former login key: %s", warning("Warning"), info(current.keyName));
    }

    writeLoginKey(loginKey);

    logInfo("%s: %s - Registered new key: %s", info("Login"), success("OK"),
        info(loginKey.keyName));

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
    logInfo("    dop login [LOGIN KEY]");
    logInfo("");
    logInfo("[LOGIN KEY] is a signed key that must be obtained from the registry");
    return code;
}
