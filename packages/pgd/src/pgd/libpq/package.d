/// bindings to libpq-14.3
module pgd.libpq;

public import pgd.libpq.bindings;
public import pgd.libpq.defs;

PGconn* PQsetdb(const(char)* pghost, const(char)* pgport, const(char)* pgoptions,
    const(char)* pgtty, const(char)* dbName)
{
    pragma(inline, true)
    return PQsetdbLogin(pghost, pgport, pgoptions, pgtty, dbName, null, null);
}
