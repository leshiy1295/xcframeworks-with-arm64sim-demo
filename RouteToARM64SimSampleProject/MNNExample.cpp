//
//  MNNExample.cpp
//  RouteToARM64SimSampleProject
//
//  Created by Aleksey Khalaidzhi on 07.10.2022.
//

#include <MNN/Matrix.h>
#include <iostream>

__attribute__((constructor))
static void hello_from_mnn_example() {
    std::cout << "Hello from MNN example\n";
    auto m = MNN::CV::Matrix{};
    m.MakeTrans(5, 10);
    m.setRotate(42);
    m.MakeScale(5);
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 3; ++j) {
            printf("%8.4f ", m[i * 3 + j]);
        }
        std::cout << std::endl;
    }
}
