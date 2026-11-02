cmake_minimum_required(VERSION 3.16)
project(Caelestia)

option(CAELESTIA_BUILD_LYRICS_TESTS "Build offline lyrics regression tests" OFF)
if(CAELESTIA_BUILD_LYRICS_TESTS)
    enable_testing()
    find_package(Qt6 REQUIRED COMPONENTS Test)
endif()

# Unity builds compile many small translation units together, which speeds up
# cold builds of the plugin. Opt-in: the installer enables it, while CI and
# packaging keep per-TU builds for cache friendliness.
option(CAELESTIA_UNITY_BUILD "Compile plugin sources as CMake unity builds" OFF)
if(CAELESTIA_UNITY_BUILD)
    set(CMAKE_UNITY_BUILD ON)
    set(CMAKE_UNITY_BUILD_BATCH_SIZE 16)
endif()

# Normally inherited from the top level project; defaulted here so the plugin
# can still be configured on its own.
if(NOT DEFINED INSTALL_QSCONFDIR)
    set(INSTALL_QSCONFDIR "etc/xdg/quickshell/caelestia" CACHE STRING "Quickshell config install dir")
endif()

find_package(Qt6 REQUIRED COMPONENTS ShaderTools Core Qml Gui Quick QuickControls2 Concurrent Sql Network DBus WaylandClient)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6GuiAddons REQUIRED)
find_package(KF6NetworkManagerQt REQUIRED)
find_package(KF6PulseAudioQt REQUIRED)
# Quick Share's wire protocol is Google's Nearby Connections protobufs, and its Ukey2
# handshake needs OpenSSL primitives that Qt does not expose. Both are required, unlike
# the cava provider below: the shell's QML imports Caelestia.Services.QuickShare from
# shell.qml, the utilities drawer, the Nexus registry and the quick toggles, so a build
# without the module ships a shell that refuses to load rather than one with a dead
# feature. There is no degrade path for a distribution to opt into, so the configure
# fails here instead, while it can still name what is missing.
find_package(Protobuf QUIET)
find_package(OpenSSL QUIET)
if(NOT Protobuf_FOUND OR NOT OpenSSL_FOUND)
    set(_quickshare_missing "")
    if(NOT Protobuf_FOUND)
        set(_quickshare_missing "protobuf")
    endif()
    if(NOT OpenSSL_FOUND)
        if(_quickshare_missing)
            string(APPEND _quickshare_missing " and ")
        endif()
        string(APPEND _quickshare_missing "openssl")
    endif()
    message(FATAL_ERROR
        "Quick Share needs ${_quickshare_missing}, and this shell always builds Quick "
        "Share: its QML is part of the shell, so a build without it does not start. "
        "Install protobuf and openssl (Arch), protobuf-devel and openssl-devel (Fedora), "
        "or libprotobuf-dev, protobuf-compiler and libssl-dev (Debian), then configure again.")
endif()

# Quick Share's transfer port is one value with three readers: the listener this build
# bakes it into, the setup helper the shell passes it to, and the install step, which
# reads it to write the matching firewall rule. It lives in a file for the same reason
# the M3Shapes revision does: three copies drift, one does not.
set(_QUICKSHARE_PORT_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/quickshare-port")
if(NOT EXISTS "${_QUICKSHARE_PORT_FILE}")
    message(FATAL_ERROR "Quick Share's transfer port is missing: ${_QUICKSHARE_PORT_FILE}")
endif()
file(STRINGS "${_QUICKSHARE_PORT_FILE}" QUICKSHARE_PORT LIMIT_COUNT 1)
if(NOT QUICKSHARE_PORT MATCHES "^[0-9]+$")
    message(FATAL_ERROR "Quick Share's transfer port must be a port number, not '${QUICKSHARE_PORT}'")
endif()
if(QUICKSHARE_PORT LESS 1 OR QUICKSHARE_PORT GREATER 65535)
    message(FATAL_ERROR "Quick Share's transfer port must be between 1 and 65535, not ${QUICKSHARE_PORT}")
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(Qalculate IMPORTED_TARGET libqalculate REQUIRED)
pkg_check_modules(Pipewire IMPORTED_TARGET libpipewire-0.3 REQUIRED)
pkg_check_modules(Aubio IMPORTED_TARGET aubio REQUIRED)
pkg_check_modules(Cava IMPORTED_TARGET libcava QUIET)
if(NOT Cava_FOUND)
    pkg_check_modules(Cava IMPORTED_TARGET cava QUIET)
endif()
if(NOT Cava_FOUND)
    # Arch's cava package doesn't ship a .pc file -- find the library
    # and header directly as a fallback.
    find_library(Cava_LIBRARY NAMES cava libcava)
    find_path(Cava_INCLUDE_DIR NAMES cava/cavacore.h)
    if(Cava_LIBRARY AND Cava_INCLUDE_DIR)
        add_library(PkgConfig::Cava UNKNOWN IMPORTED)
        set_target_properties(PkgConfig::Cava PROPERTIES
            IMPORTED_LOCATION "${Cava_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${Cava_INCLUDE_DIR}"
        )
        set(Cava_FOUND TRUE)
        message(STATUS "Found cava (via find_library): ${Cava_LIBRARY}")
    endif()
endif()

# The provider is compiled only when cava's headers and library are there, so a build
# without them ships a shell whose visualiser is dead: no error, nothing in the package
# to say so, and at runtime only "CavaProvider unavailable, visualiser disabled" in the
# journal. A distribution build that means to include it asks for it and fails here
# instead, where the message can name what is missing. A developer build leaves it off
# and gets the provider or not, as the machine allows.
option(REQUIRE_CAVA "Fail the configure when libcava is missing" OFF)
if(NOT Cava_FOUND AND REQUIRE_CAVA)
    message(FATAL_ERROR
        "libcava was not found and REQUIRE_CAVA is on: this build would leave out the "
        "audio visualiser. Install libcava (its headers, its shared library and its "
        "pkg-config file) and configure again. Note that Arch's `cava` package ships only "
        "the cava executable - the library comes from the separate libcava package.")
endif()
include(cmake/sensorslib.cmake)

set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml")
qt_standard_project_setup(REQUIRES 6.9)

include(cmake/pch.cmake)
include(cmake/qml-module.cmake)

# Header only helpers
add_library(caelestia-util INTERFACE)
target_include_directories(caelestia-util INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")

add_subdirectory(src/Caelestia)
