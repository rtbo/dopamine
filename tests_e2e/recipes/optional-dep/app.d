module app;

import std.stdio;

version (Have_pkgb)
{
    import pkgb;
}

void main()
{
    int printed = 1;
    version(Have_pkgb)
        printed = stableB(printed);

    writeln(printed);
}
