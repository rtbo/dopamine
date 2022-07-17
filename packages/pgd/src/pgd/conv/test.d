/// Tests that would normally go to pgd/conv/package.d
module pgd.conv.test;

version (unittest)  : import pgd.conn;
import pgd.conv;
import pgd.maybe;
import pgd.libpq.defs;
import pgd.test;

import std.typecons;

@("pgQueryParams")
unittest
{
    int i = 21;
    string s = "blabla";
    MayBe!(string, null) ns;
    ubyte[] blob = [4, 5, 6, 7];
    int* pi;
    Nullable!int ni = 12;

    auto params = pgQueryParams(i, s, ns, blob, pi, ni);

    assert(cast(TypeOid[]) params.oids == [
            TypeOid.INT4, TypeOid.TEXT, TypeOid.TEXT, TypeOid.BYTEA, TypeOid.INT4,
            TypeOid.INT4
        ]);
    assert(params.lengths == [4, 6, 0, 4, 0, 4]);
    assert(params.values.length == 6);
    assert(params.values[0]!is null);
    assert(params.values[1]!is null);
    assert(params.values[2] is null);
    assert(params.values[3]!is null);
    assert(params.values[4] is null);
    assert(params.values[5]!is null);
}

@("conversions")
unittest
{
    auto db = new PgConn(dbConnString());
    scope (exit)
        db.finish();

    db.exec(`
        CREATE TABLE conversions (
            i       integer,
            t       text
        )
    `);
    scope (exit)
        db.exec(`DROP TABLE conversions`);


    Nullable!int nullI;
    MayBeText nullT;

    db.exec(`
        INSERT INTO conversions (i, t)
        VALUES ($1, $2), ($3, $4), ($5, $6),
        (1, 'one'), (NULL, 'two'), (3, NULL)
    `, 1, "one", nullI, "two", 3, nullT);

    @OrderedCols
    struct R
    {
        MayBe!int i;
        Nullable!string t;
    }

    const r = db.execRows!R(`
        SELECT i, t FROM conversions
    `);

    assert(r.length == 6);
    assert(r[0].i.value == 1);
    assert(r[0].t.get == "one");
    assert(!r[1].i.valid);
    assert(r[1].t.get == "two");
    assert(r[2].i.value == 3);
    assert(r[2].t.isNull);
    assert(r[3].i.value == 1);
    assert(r[3].t.get == "one");
    assert(!r[4].i.valid);
    assert(r[4].t.get == "two");
    assert(r[5].i.value == 3);
    assert(r[5].t.isNull);
}
