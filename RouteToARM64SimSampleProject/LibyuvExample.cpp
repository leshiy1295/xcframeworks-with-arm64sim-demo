//
//  LibyuvExample.cpp
//  RouteToARM64SimSampleProject
//
//  Created by Aleksey Khalaidzhi on 07.10.2022.
//

#include <libyuv.h>

#include <iostream>

__attribute__((constructor))
static void hello_from_libyuv_example() {
    std::cout << "Hello from libyuv example\n";
    static const size_t kSize = 5;

    const uint8_t src_a[kSize] = {1, 2, 3, 4, 5};
    const uint8_t src_b[kSize] = {1, 3, 2, 4, 5};
    std::cout << "a = ";
    for (const auto &a_elem : src_a) { std::cout << static_cast<int>(a_elem) << " "; };
    std::cout << "\n";
    std::cout << "b = ";
    for (const auto &b_elem : src_b) { std::cout << static_cast<int>(b_elem) << " "; };
    std::cout << "\n";
    std::cout << "SumSquareError(a, b) = " << libyuv::ComputeSumSquareError(src_a, src_b, kSize) << "\n";
}
