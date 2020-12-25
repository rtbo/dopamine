module app;

import lib;

enum imported = import("import.txt");
static assert(imported == "Imported text");

int main()
{
    lib_print_root(1522756.0);
    return lib_calc_square(4) - 16;
}
