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
        clipboardmanager.cpp
        clipboardmanager.hpp
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
