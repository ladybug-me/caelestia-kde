cmake_minimum_required(VERSION 3.19)

# The release version lives in .github/version.env - the single source of
# truth (read by CI and the installer/updater scripts). It is loaded here so a
# bump is a one-line change to version.env; shell/CMakeLists.txt must never
# carry its own copy of the release number. An explicit -DVERSION=... on the
# configure line still wins for packaging.
if(NOT DEFINED VERSION)
    set(_VERSION_ENV "${CMAKE_SOURCE_DIR}/../.github/version.env")
    if(EXISTS "${_VERSION_ENV}")
        file(STRINGS "${_VERSION_ENV}" _VER_LINE REGEX "^VERSION=")
        if(_VER_LINE)
            string(REGEX REPLACE "^VERSION=" "" VERSION "${_VER_LINE}")
        endif()
        # file(STRINGS) is not tracked as a configure input, so re-run
        # configure whenever version.env changes. Without this an existing
        # build dir would keep baking the previous version after a bump.
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_VERSION_ENV}")
    endif()

    # Fallback for a tree without version.env (e.g. a standalone shell
    # checkout): the nearest git tag. No maintenance needed.
    if(NOT VERSION OR "${VERSION}" STREQUAL "" OR "${VERSION}" STREQUAL "rolling")
        execute_process(COMMAND git describe --tags --match "v*" --abbrev=0
            WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
            OUTPUT_VARIABLE VERSION
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
    endif()

    # Nothing left to derive from (no version.env, no git): keep VERSION empty
    # instead of hardcoding a release number that would drift. Consumers
    # degrade cleanly (CUtils.version reports an unknown version).
    string(STRIP "${VERSION}" VERSION)
endif()

if(NOT DEFINED GIT_REVISION)
    # A source tarball has no .git to ask. The release job writes REVISION beside
    # version.env with the commit the tag points at, so a package built from a tarball
    # reports the same revision a checkout would instead of "unknown".
    set(_REVISION_FILE "${CMAKE_SOURCE_DIR}/../REVISION")
    if(EXISTS "${_REVISION_FILE}")
        file(STRINGS "${_REVISION_FILE}" GIT_REVISION LIMIT_COUNT 1)
        string(STRIP "${GIT_REVISION}" GIT_REVISION)
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_REVISION_FILE}")
    else()
        execute_process(COMMAND git rev-parse HEAD
            WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
            OUTPUT_VARIABLE GIT_REVISION
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
    endif()

    if("${GIT_REVISION}" STREQUAL "")
        set(GIT_REVISION "unknown")
    endif()
endif()

set(DISPLAY_VERSION "${VERSION}")

# On dev branch: append -dev+<short-hash> to distinguish from stable
execute_process(COMMAND git rev-parse --abbrev-ref HEAD
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    OUTPUT_VARIABLE _GIT_BRANCH
    OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET
)
if("${_GIT_BRANCH}" STREQUAL "dev")
    execute_process(COMMAND git rev-parse --short HEAD
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        OUTPUT_VARIABLE _SHORT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET
    )
    if(NOT "${_SHORT_HASH}" STREQUAL "")
        set(DISPLAY_VERSION "${VERSION}-dev+${_SHORT_HASH}")
    endif()
endif()

string(REGEX REPLACE "^v" "" VERSION "${VERSION}")
string(REGEX REPLACE "^v" "" DISPLAY_VERSION "${DISPLAY_VERSION}")

# Only hand VERSION to project() when we actually derived one. An empty
# version is valid here (consumers report an unknown version) but is not a
# legal project() VERSION argument.
if(VERSION)
    project(caelestia-shell VERSION ${VERSION} LANGUAGES C CXX)
else()
    project(caelestia-shell LANGUAGES C CXX)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Use ccache if available for dramatically faster rebuilds
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    message(STATUS "ccache found — compiler caching enabled")
endif()

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

set(DISTRIBUTOR "Unset" CACHE STRING "Distributor")
set(ENABLE_MODULES "extras;plugin;shell;m3shapes" CACHE STRING "Modules to build/install")
set(INSTALL_LIBDIR "usr/lib/caelestia" CACHE STRING "Library install dir")
set(INSTALL_QMLDIR "usr/lib/qt6/qml" CACHE STRING "QML install dir")
set(INSTALL_QSCONFDIR "etc/xdg/quickshell/caelestia" CACHE STRING "Quickshell config install dir")

# The M3Shapes checkout is external and builds its strings from raw literals, so it
# is configured before the strict casts below apply: directory definitions are
# inherited when a subdirectory is created, and the fetch creates one.
if("m3shapes" IN_LIST ENABLE_MODULES)
    message(STATUS "Fetching M3Shapes module")
    include(FetchContent)
    set(M3SHAPES_REV bdc327b29f95394a732baf3c9b19658ba23755b6)

    # Opt-in persistent checkout. When enabled, the source is cloned into the
    # user cache so wiping the build dir doesn't force a re-clone (the
    # installer enables this). Off by default so CI/packaging/reproducible
    # builds keep sources inside the build tree via FetchContent's default
    # _deps location.
    option(CAELESTIA_CACHE_DEPS "Keep FetchContent sources outside the build tree" OFF)

    if(CAELESTIA_CACHE_DEPS)
        if(DEFINED ENV{XDG_CACHE_HOME} AND NOT "$ENV{XDG_CACHE_HOME}" STREQUAL "")
            set(_CAELESTIA_CACHE "$ENV{XDG_CACHE_HOME}/caelestia-kde")
        else()
            set(_CAELESTIA_CACHE "$ENV{HOME}/.cache/caelestia-kde")
        endif()
        set(_M3SHAPES_SOURCE_DIR "${_CAELESTIA_CACHE}/m3shapes-${M3SHAPES_REV}")
    else()
        set(_M3SHAPES_SOURCE_DIR "${CMAKE_BINARY_DIR}/_deps/m3shapes-${M3SHAPES_REV}")
    endif()

    FetchContent_Declare(
        m3shapes_external
        GIT_REPOSITORY https://github.com/soramanew/m3shapes.git
        GIT_TAG        ${M3SHAPES_REV}
        SOURCE_DIR     "${_M3SHAPES_SOURCE_DIR}"
    )
    FetchContent_MakeAvailable(m3shapes_external)
    message(STATUS "Done fetching M3Shapes module")

    # Fix m3shapes wrong rpath
    if(TARGET m3shapesplugin)
        set_target_properties(m3shapesplugin PROPERTIES INSTALL_RPATH "$ORIGIN")
    endif()
endif()

# An implicit const char* to QString conversion hides a decision about encoding:
# QStringLiteral/QLatin1String/fromUtf8 have to be written out instead.
add_compile_definitions(
    QT_NO_CAST_FROM_ASCII
    QT_NO_CAST_TO_ASCII
    QT_NO_CAST_FROM_BYTEARRAY
)

add_compile_options(
    -Wall -Wextra -Wpedantic -Wshadow -Wconversion
    -Wold-style-cast -Wnull-dereference -Wdouble-promotion
    -Wformat=2 -Wfloat-equal -Woverloaded-virtual
    -Wsign-conversion -Wredundant-decls -Wswitch
    -Wunreachable-code
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    add_compile_options(-Wunused-lambda-capture)
endif()

if("extras" IN_LIST ENABLE_MODULES)
    add_subdirectory(extras)
endif()

if("plugin" IN_LIST ENABLE_MODULES)
    add_subdirectory(plugin)
endif()

if("shell" IN_LIST ENABLE_MODULES)
    foreach(dir assets components modules scripts services utils)
        install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${dir}
                DESTINATION ${INSTALL_QSCONFDIR})
    endforeach()

    install(PROGRAMS assets/wrap_term_launch.sh DESTINATION "${INSTALL_QSCONFDIR}/assets")

    file(READ shell.qml SHELL_QML)
    string(REPLACE "settings.watchFiles: true" "settings.watchFiles: false" SHELL_QML "${SHELL_QML}")
    file(WRITE "${CMAKE_BINARY_DIR}/qml/shell.qml" "${SHELL_QML}")
    install(FILES "${CMAKE_BINARY_DIR}/qml/shell.qml" DESTINATION "${INSTALL_QSCONFDIR}")

    install(FILES LICENSE DESTINATION "${INSTALL_QSCONFDIR}")

    # Translations: compile every translations/*.ts into a .qm next to the
    # installed shell, where the Translations singleton looks for them.
    #
    # Compiled catalogues are committed alongside their sources, so a build
    # without Qt's Linguist tools installs those instead of quietly dropping
    # every language but English -- a missing build tool is not something a
    # user can be expected to connect to a language having disappeared from
    # the picker. When lrelease is present the .ts files are recompiled and
    # win, so an edited translation never has to wait for someone to refresh
    # the committed artefact.
    find_package(Qt6 QUIET COMPONENTS LinguistTools)
    file(GLOB TS_FILES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/translations/*.ts")
    file(GLOB PREBUILT_QM_FILES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/translations/*.qm")

    if(Qt6LinguistTools_FOUND AND TS_FILES)
        set(QM_DIR "${CMAKE_BINARY_DIR}/translations")
        set(QM_FILES "")

        foreach(ts_file ${TS_FILES})
            get_filename_component(ts_name "${ts_file}" NAME_WE)
            set(qm_file "${QM_DIR}/${ts_name}.qm")
            add_custom_command(
                OUTPUT "${qm_file}"
                COMMAND "${CMAKE_COMMAND}" -E make_directory "${QM_DIR}"
                COMMAND Qt6::lrelease -silent "${ts_file}" -qm "${qm_file}"
                DEPENDS "${ts_file}"
                COMMENT "Compiling translation ${ts_name}.qm"
                VERBATIM
            )
            list(APPEND QM_FILES "${qm_file}")
        endforeach()

        add_custom_target(caelestia-translations ALL DEPENDS ${QM_FILES})
        install(FILES ${QM_FILES} DESTINATION "${INSTALL_QSCONFDIR}/translations")
    elseif(PREBUILT_QM_FILES)
        message(STATUS "Qt Linguist tools not found - installing the committed catalogues as-is")
        install(FILES ${PREBUILT_QM_FILES} DESTINATION "${INSTALL_QSCONFDIR}/translations")
    elseif(TS_FILES)
        message(WARNING "Qt Linguist tools not found and no compiled catalogues - the shell will only be available in English")
    endif()
endif()
