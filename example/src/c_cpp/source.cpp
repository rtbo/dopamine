#include "header.hpp"

#include <cmath>
#include <iostream>

namespace lib
{
    int calc_square(int x) {
        return x*x;
    }

    void print_root(double x) {
        std::cout << "square root of " << x << " is " << std::sqrt(x) << std::endl;
    }
}
