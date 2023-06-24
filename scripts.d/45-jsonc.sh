#!/bin/bash

SCRIPT_REPO="https://github.com/json-c/json-c"
SCRIPT_COMMIT="2f2ddc1f2dbca56c874e8f9c31b5b963202d80e7"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    cd "$FFBUILD_DLDIR/$SELF"

    cmake -B build -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON
    cmake --build build --config Release
    cd build
    make install
}


ffbuild_ldflags() {
    echo "-ljson-c "
}
