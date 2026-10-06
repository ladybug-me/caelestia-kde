cmake_minimum_required(VERSION 3.10)
project(CaelestiaInstaller CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED True)

option(CAELESTIA_ENABLE_SANITIZERS "Enable AddressSanitizer and UBSan" OFF)

# Use ccache if available for dramatically faster rebuilds
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    message(STATUS "ccache found — compiler caching enabled")
endif()

# Set compile flags
set(CMAKE_CXX_FLAGS_RELEASE "-O2")

# Find all source files
file(GLOB SOURCES "*.cpp")
list(FILTER SOURCES EXCLUDE REGEX "StepPolicyTests\\.cpp$")
include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# Define executable
add_executable(caelestia-install ${SOURCES})

enable_testing()
add_executable(step-policy-tests StepPolicyTests.cpp StepPolicy.cpp)
add_test(NAME step-policy-tests COMMAND step-policy-tests)

if(CAELESTIA_ENABLE_SANITIZERS)
    target_compile_options(caelestia-install PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(caelestia-install PRIVATE -fsanitize=address,undefined)
    target_compile_options(step-policy-tests PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(step-policy-tests PRIVATE -fsanitize=address,undefined)
endif()
