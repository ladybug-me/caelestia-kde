pragma ComponentBehavior: Bound

import "../drawers/blur" as Blur
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

Variants {
    model: Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled)

    StyledWindow {
        id: win

        required property ShellScreen modelData
        readonly property var drawerVisibilities: Visibilities.screens.get(Kwin.monitorFor(modelData)) ?? Visibilities.screens.get(modelData.name)
        readonly property bool isOverviewOpen: drawerVisibilities ? drawerVisibilities.overview : false
        readonly property bool wallpaperUp: wallpaper.item?.shown ?? false
        property bool wallpaperHasBeenUp: false

        onWallpaperUpChanged: {
            if (wallpaperUp)
                wallpaperHasBeenUp = true;
        }

        screen: modelData
        name: "background"
        isDesktopWidget: true
        color: (Config.background.wallpaperEnabled && wallpaperHasBeenUp) ? "black" : "transparent"
        surfaceFormat.opaque: false
        mask: Config.background.wallpaperEnabled ? null : emptyRegion
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        Region {
            id: emptyRegion

            width: 0
            height: 0
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onTapped: (eventPoint, button) => {
                if (desktopIcons.renameActive)
                    desktopIcons.renamingDelegate?.commitRename();
                const onEmptyDesktop = Config.background.wallpaperEnabled && !desktopIcons.iconAt(eventPoint.position.x, eventPoint.position.y);
                if (button === Qt.RightButton && onEmptyDesktop) {
                    ContextMenuStore.openDesktopContextMenu(eventPoint.position.x, eventPoint.position.y, win.modelData.name);
                } else if (button === Qt.MiddleButton && onEmptyDesktop) {
                    // Middle click on empty desktop shows or hides the icons.
                    ContextMenuStore.toggleIcons(win.modelData.name);
                } else if (button === Qt.LeftButton) {
                    if (true) {
                        Kwin.setActiveOutputName(win.screen.name);
                    }
                }
            }
        }
        Item {
            id: behindClock

            anchors.fill: parent

            Loader {
                id: wallpaper

                asynchronous: true
                anchors.fill: parent
                active: Config.background.wallpaperEnabled
                sourceComponent: Wallpaper {
                    screen: win.modelData
                }
            }
            Visualiser {
                anchors.fill: parent
                screen: win.modelData
                wallpaper: wallpaper
                z: 2
                visible: true
            }
        }
        DesktopIcons {
            id: desktopIcons

            screenData: win.modelData
            wallpaper: behindClock
            z: 3
        }
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: desktopIcons.renameActive ? WlrKeyboardFocus.Exclusive : desktopIcons.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    }
}
