/// bindings to libpq-14.3
module dopamine.c.libpq;

public import dopamine.c.libpq.bindings;
public import dopamine.c.libpq.types;

PGconn* PQsetdb(const(char)* pghost, const(char)* pgport, const(char)* pgoptions,
    const(char)* pgtty, const(char)* dbName)
{
    pragma(inline, true)
    return PQsetdbLogin(pghost, pgport, pgoptions, pgtty, dbName, null, null);
}
