/// Tests that would normally go to pgd/conv/package.d
module pgd.conv.test;

version(unittest):

import pgd.conv;
import pgd.maybe;
import pgd.libpq.defs;

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
