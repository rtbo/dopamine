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
bool IsPolymorphicType(Oid typid)
{
    return IsPolymorphicTypeFamily1(typid) || IsPolymorphicTypeFamily2(typid);
}

/* Code not part of polymorphic type resolution should not use these macros: */
bool IsPolymorphicTypeFamily1(Oid typid)
{
    return typid == ANYELEMENTOID ||
        typid == ANYARRAYOID ||
        typid == ANYNONARRAYOID ||
        typid == ANYENUMOID ||
        typid == ANYRANGEOID ||
        typid == ANYMULTIRANGEOID;
}

bool IsPolymorphicTypeFamily2(Oid typid)
{
    return typid == ANYCOMPATIBLEOID ||
        typid == ANYCOMPATIBLEARRAYOID ||
        typid == ANYCOMPATIBLENONARRAYOID ||
        typid == ANYCOMPATIBLERANGEOID ||
        typid == ANYCOMPATIBLEMULTIRANGEOID;
}
