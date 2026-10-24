# Top-level build for all Mac apps in this repo.
#
#   scripts/build.sh            (preferred; finds the toolchain for you)
#
# or by hand:
#
#   cmake -S apps -B build/apps -G Ninja \
#     -DCMAKE_TOOLCHAIN_FILE=$RETRO68_TOOLCHAIN/m68k-apple-macos/cmake/retro68.toolchain.cmake
#   cmake --build build/apps

cmake_minimum_required(VERSION 3.13)
project(MacApps C CXX)

if(NOT CMAKE_SYSTEM_NAME MATCHES Retro68)
    message(FATAL_ERROR "Configure with the Retro68 68k toolchain file (see scripts/build.sh)")
endif()

# Every app targets a 68000 Mac SE: no 68020+ instructions, no FPU.
add_compile_options(-m68000 -Wall)

add_subdirectory(hello)
