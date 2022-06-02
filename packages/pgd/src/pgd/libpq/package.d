/// bindings to libpq-14.3
module pgd.libpq;

public import pgd.libpq.bindings;
public import pgd.libpq.defs;

// libpq-fe.h
@system PGconn* PQsetdb(const(char)* pghost, const(char)* pgport, const(char)* pgoptions,
    const(char)* pgtty, const(char)* dbName)
{
    pragma(inline, true)
    return PQsetdbLogin(pghost, pgport, pgoptions, pgtty, dbName, null, null);
}

@safe:

// pg_type_d.h

/* Is a type OID a polymorphic pseudotype?	(Beware of multiple evaluation) */
bool IsPolymorphicType(TypeOid typid)
{
    return IsPolymorphicTypeFamily1(typid) || IsPolymorphicTypeFamily2(typid);
}

/* Code not part of polymorphic type resolution should not use these macros: */
bool IsPolymorphicTypeFamily1(TypeOid typid)
{
    return typid == TypeOid.ANYELEMENT ||
        typid == TypeOid.ANYARRAY ||
        typid == TypeOid.ANYNONARRAY ||
        typid == TypeOid.ANYENUM ||
        typid == TypeOid.ANYRANGE ||
        typid == TypeOid.ANYMULTIRANGE;
}

bool IsPolymorphicTypeFamily2(TypeOid typid)
{
    return typid == TypeOid.ANYCOMPATIBLE ||
        typid == TypeOid.ANYCOMPATIBLEARRAY ||
        typid == TypeOid.ANYCOMPATIBLENONARRAY ||
        typid == TypeOid.ANYCOMPATIBLERANGE ||
        typid == TypeOid.ANYCOMPATIBLEMULTIRANGE;
}
