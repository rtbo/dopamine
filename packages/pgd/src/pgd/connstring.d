module pgd.connstring;

import pgd.libpq;

import std.format;
import std.string;

@safe:

string[string] breakdownConnString(string conninfo) @trusted
{
    const conninfoz = conninfo.toStringz();

    char* errmsg;
    PQconninfoOption* opts = PQconninfoParse(conninfoz, &errmsg);

    if (!opts)
    {
        const msg = errmsg.fromStringz().idup;
        throw new Exception("Could not parse connection string: " ~ msg);
    }

    scope (exit)
        PQconninfoFree(opts);

    string[string] res;

    for (auto opt = opts; opt && opt.keyword; opt++)
        if (opt.val)
            res[opt.keyword.fromStringz().idup] = opt.val.fromStringz().idup;

    return res;
}

string assembleConnString(const(string[string]) connInfo)
{
    import std.algorithm : filter, map;
    import std.array : join;

    const user = connInfo.get("user", null);
    const pswd = connInfo.get("password", null);
    const userSpec = (user || pswd) ? format!"%s%s%s@"(user, pswd ? ":" : "", pswd) : "";

    const host = connInfo.get("host", null);
    const port = connInfo.get("port", null);
    const hostSpec = (host || port) ? format!"%s%s%s"(host, port ? ":" : "", port) : "";

    const dbname = connInfo.get("dbname", null);
    const dbSpec = dbname ? format!"/%s"(dbname) : "";

    const paramSpec = connInfo.byKeyValue()
        .filter!(kv => kv.key != "user")
        .filter!(kv => kv.key != "password")
        .filter!(kv => kv.key != "host")
        .filter!(kv => kv.key != "port")
        .filter!(kv => kv.key != "dbname")
        .map!(kv => format!"%s=%s"(kv.key, kv.value))
        .join("&");

    return format!"postgres://%s%s%s%s%s"(userSpec, hostSpec, dbSpec, paramSpec ? "?" : "", paramSpec);
}

version (unittest) import unit_threaded.assertions;

@("breakdownConnString, assembleConnString")
unittest
{
    const str0 = "postgres://";
    const string[string] info0;

    const str1 = "postgres:///adatabase";
    const string[string] info1 = ["dbname": "adatabase"];

    const str2 = "postgres://somehost:3210/adatabase";
    const string[string] info2 = [
        "host": "somehost",
        "port": "3210",
        "dbname": "adatabase",
    ];

    const str3 = "postgres://someuser@somehost:3210/adatabase";
    const string[string] info3 = [
        "user": "someuser",
        "host": "somehost",
        "port": "3210",
        "dbname": "adatabase",
    ];

    info0.shouldEqual(breakdownConnString(str0));
    info1.shouldEqual(breakdownConnString(str1));
    info2.shouldEqual(breakdownConnString(str2));
    info3.shouldEqual(breakdownConnString(str3));

    str0.shouldEqual(assembleConnString(info0));
    str1.shouldEqual(assembleConnString(info1));
    str2.shouldEqual(assembleConnString(info2));
    str3.shouldEqual(assembleConnString(info3));
}
