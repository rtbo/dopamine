module pkgb;

extern(C) int funca(int x);

int pkgb(int x)
{
    return 3 * funca(x);
}

int stableB(int x)
{
    return 3 * x;
}
