module pkgb;

extern(C) int funca(int x);

int pkgb(int x)
{
    return 6 * funca(x);
}
