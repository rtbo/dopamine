#include "header.h"
#include "header.hpp"

extern "C" {

    int lib_calc_square(int x) {
        return lib::calc_square(x);
    }

    void lib_print_root(double x) {
        lib::print_root(x);
    }

}
