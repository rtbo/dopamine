module dopamine.util;

@safe:

package:

size_t indexOrLast(string s, char c) pure
{
    import std.string : indexOf;

    const ind = s.indexOf(c);
    return ind >= 0 ? ind : s.length;
}
