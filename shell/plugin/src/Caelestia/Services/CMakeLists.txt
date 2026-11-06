find_package(KF6GlobalAccel REQUIRED)
find_package(KF6Config REQUIRED)
find_package(KF6NetworkManagerQt REQUIRED)
find_package(X11 REQUIRED)
# For QPlatformNativeInterface, the only way to reach a QWindow's wl_surface:
# Qt exposes no public native interface for it. Ships with qt6-base on Arch and
# with qt6-qtbase-private-devel on Fedora, both already installed by setup.
find_package(Qt6 REQUIRED COMPONENTS GuiPrivate)
# Cava audio visualizer — optional on systems where it's not packaged.
set(CAVA_SOURCES "")
set(CAVA_LIBRARIES "")
if(Cava_FOUND)
    list(APPEND CAVA_SOURCES cavaprovider.cpp cavaprovider.hpp)
    list(APPEND CAVA_LIBRARIES PkgConfig::Cava)
endif()

# KRunner powers the launcher's system-wide search: files, recent documents,
# places, bookmarks, web shortcuts, the dictionary, unit and currency conversion
# and settings modules. Optional on purpose — KRunner's D-Bus service exposes only
# UI control, so this needs the library, and a distribution without libKF6Runner
# should still build a shell whose launcher simply lacks that one mode.
find_package(KF6Runner QUIET)
if(NOT KF6Runner_FOUND)
    # Say it out loud: the installers' package lists are the only thing keeping this
    # from happening quietly, and a distro they do not know about would lose the
    # launcher's search mode with nothing in the build output to show for it.
    message(STATUS "KF6Runner not found: the launcher will build without system search")
endif()

qml_module(caelestia-services
    URI Caelestia.Services
    SOURCES
        service.cpp
        serviceref.cpp
        beattracker.cpp
        audiocollector.cpp
        audioprovider.cpp
        audiodevicebackend.cpp
        audiodevicebackend.hpp
        ${CAVA_SOURCES}
        tickingservice.cpp
        sensorslib.cpp
        networkusage.cpp
        networkusage.hpp
        cpu.cpp
        gpu.cpp
        memory.cpp
        diskinfo.cpp
        storage.cpp
        weather.cpp
        weather.hpp
        lyriccandidate.cpp
        lyrics.cpp
        sessionmanager.cpp
        sessionmanager.hpp
        discordipc.cpp
        discordipc.hpp
        hyprdevices.cpp
        hyprdevices.hpp
        hyprextras.cpp
        hyprextras.hpp
        keybindsmodel.cpp
        keybindsmodel.hpp
        emojidb.cpp
        emojidb.hpp
        brightnesswatcher.cpp
        brightnesswatcher.hpp
        pipewirestreamwatcher.cpp
        pipewirestreamwatcher.hpp
        clipboardmanager.cpp
        clipboardmanager.hpp
        krunnerbridge.cpp
        krunnerbridge.hpp
        schemeloader.cpp
        schemeloader.hpp
        palettemanager.cpp
        palettemanager.hpp
        dinogame.cpp
        dinogame.hpp
        kwinworkspacestate.cpp
        kwinworkspacestate.hpp
        kwinactivewindowbridge.cpp
        windowicon.cpp
        kwinactivewindowbridge.hpp
        nightcolorbridge.cpp
        nightcolorbridge.hpp
        globalshortcut.cpp
        globalshortcut.hpp
        krohnkiteconfig.cpp
        krohnkiteconfig.hpp
        launcherentry.cpp
        launcherentry.hpp
        windowscreencast.cpp
        windowscreencast.hpp
        windowstream.cpp
        windowstream.hpp
        windowicon.hpp
        minimizegeometry.cpp
        minimizegeometry.hpp
        plasmawindows.cpp
        plasmawindows.hpp
        plasmawindowicon.cpp
        plasmawindowicon.hpp
        screenedges.cpp
        screenedges.hpp
        NmQt.cpp
        NmQt.hpp
        HotspotController.cpp
        HotspotController.hpp
    LIBRARIES
        Qt::Concurrent
        Qt::DBus
        Qt::Network
        Qt::Gui
        Qt::Quick
        Qt::GuiPrivate
        Qt::WaylandClient
        KF6::GlobalAccel
        KF6::ConfigCore
        X11::X11
        PkgConfig::Pipewire
        PkgConfig::Aubio
        ${CAVA_LIBRARIES}
        Sensors::Sensors
        KF6::NetworkManagerQt
        KF6::PulseAudioQt
        caelestia-core
        caelestia-config
)

if(KF6Runner_FOUND)
    target_link_libraries(caelestia-services PRIVATE KF6::Runner)
    target_compile_definitions(caelestia-services PRIVATE CAELESTIA_HAVE_KRUNNER)
endif()

qt6_generate_wayland_protocol_client_sources(caelestia-services FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/../protocols/zkde-screencast-unstable-v1.xml
    ${CMAKE_CURRENT_SOURCE_DIR}/../protocols/plasma-window-management.xml
    ${CMAKE_CURRENT_SOURCE_DIR}/../protocols/kde-output-device-v2.xml
    ${CMAKE_CURRENT_SOURCE_DIR}/../protocols/kde-output-management-v2.xml
)
set_source_files_properties(
    ${CMAKE_CURRENT_BINARY_DIR}/wayland-zkde-screencast-unstable-v1-protocol.c
    ${CMAKE_CURRENT_BINARY_DIR}/wayland-plasma-window-management-protocol.c
    ${CMAKE_CURRENT_BINARY_DIR}/wayland-kde-output-device-v2-protocol.c
    ${CMAKE_CURRENT_BINARY_DIR}/wayland-kde-output-management-v2-protocol.c
    PROPERTIES SKIP_PRECOMPILE_HEADERS ON
)

add_subdirectory(QuickShare)

if(CAELESTIA_BUILD_LYRICS_TESTS)
    qt_add_executable(caelestia-lyrics-test ../../../tests/lyrics-test.cpp)
    target_include_directories(caelestia-lyrics-test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries(caelestia-lyrics-test PRIVATE caelestia-services caelestia-config Qt6::Test Qt6::Network Qt6::Qml)
    add_test(NAME lyrics-regressions COMMAND caelestia-lyrics-test)
    set_tests_properties(lyrics-regressions PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
