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
        logInfo("replacing former login key: '%s'", warning(current.keyName));
    }

    logInfo("registering new login key: '%s'", success(loginKey.keyName));

    writeLoginKey(loginKey);

    return 0;
}
