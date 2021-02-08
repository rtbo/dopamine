module dopamine.client.login;

import dopamine.log;
import dopamine.login;

import std.exception;
import std.stdio;

int loginMain(string[] args)
{
    enforce(args.length == 2, "dop login must be called with the key as argument");

    const key = args[1];
    const loginKey = decodeLoginKey(key);

    if (isLoggedIn()) {
        const current = readLoginKey();
        logInfo("%s: Replacing former login key: %s", warning("Warning"), info(current.keyName));
    }

    writeLoginKey(loginKey);

    logInfo("%s: %s - Registered new key: %s", info("Login"), success("OK"), info(loginKey.keyName));

    return 0;
}
