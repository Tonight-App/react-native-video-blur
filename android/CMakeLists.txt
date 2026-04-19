project(BlurredVideo)
cmake_minimum_required(VERSION 3.9.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(PACKAGE_NAME BlurredVideo)

# Create the .so library that the Kotlin side loads via System.loadLibrary("BlurredVideo").
# Nitrogen-generated autolinking.cmake appends all required sources, headers and
# links against react-native-nitro-modules + the base RN libs for us.
add_library(${PACKAGE_NAME} SHARED src/main/cpp/cpp-adapter.cpp)

include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/BlurredVideo+autolinking.cmake)
