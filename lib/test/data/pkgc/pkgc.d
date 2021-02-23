module pkgc;

extern(C) int funca(int x);

int funcc(int x)
{
    return funca(x) / 2;
}

@("funcc")
unittest
{
    assert(funcc(4) == 4);
}
