/// Tests that would normally go to pgd/conv/package.d
module pgd.conv.test;

version (unittest):

import pgd.conn;
import pgd.conv;
import pgd.maybe;
import pgd.test;

import std.typecons;

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
