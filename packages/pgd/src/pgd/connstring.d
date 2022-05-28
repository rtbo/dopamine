module pgd.connstring;

import pgd.libpq;

import std.string;

string[string] breakdownConnString(string conninfo)
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

version (unittest) import unit_threaded.assertions;

@("breakdownConnString")
unittest
{
    const bd0 = breakdownConnString("postgres://");
    const string[string] exp0;

    const bd1 = breakdownConnString("postgres:///adatabase");
    const string[string] exp1 = ["dbname": "adatabase"];

    const bd2 = breakdownConnString("postgres://somehost:3210/adatabase");
    const string[string] exp2 = [
        "host": "somehost",
        "port": "3210",
        "dbname": "adatabase",
    ];

    const bd3 = breakdownConnString("postgres://someuser@somehost:3210/adatabase");
    const string[string] exp3 = [
        "user": "someuser",
        "host": "somehost",
        "port": "3210",
        "dbname": "adatabase",
    ];

    bd0.shouldEqual(exp0);
    bd1.shouldEqual(exp1);
    bd2.shouldEqual(exp2);
    bd3.shouldEqual(exp3);
}
