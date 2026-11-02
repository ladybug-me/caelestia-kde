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
        property int widgetUpdateTrigger: 0

        readonly property var widgetRegions: {
            widgetUpdateTrigger;
            const list = [];
            for (let i = 0; i < bgWidgetsRepeater.count; i++) {
                const loader = bgWidgetsRepeater.itemAt(i);
                const wItem = loader?.item;
                if (!wItem)
                    continue;
                const r = wItem.inputRegions;
                if (r && Array.isArray(r)) {
                    for (const reg of r) {
                        if (reg)
                            list.push(reg);
                    }
                } else if (wItem.inputRegion) {
                    list.push(wItem.inputRegion);
                }
            }
            return list;
        }

        function applyWidgetContext(widget: var): void {
            if (!widget)
                return;

            const context = {
                screen: win.modelData,
                modelData: win.modelData,
                background: win
            };

            for (const name in context) {
                if (widget.hasOwnProperty(name))
                    widget[name] = context[name];
            }

            if (widget.inputRegionsChanged)
                widget.inputRegionsChanged.connect(() => { win.widgetUpdateTrigger++; });
        }

        onWallpaperUpChanged: {
            if (wallpaperUp)
                wallpaperHasBeenUp = true;
        }

        screen: modelData
        name: "background"
        isDesktopWidget: true
        color: (Config.background.wallpaperEnabled && wallpaperHasBeenUp && !ContextMenuStore.editMode && !Config.background.disableQuickshellDesktop) ? "black" : "transparent"
        surfaceFormat.opaque: false
        mask: {
            if (ContextMenuStore.editMode)
                return emptyRegion;
            if (Config.background.disableQuickshellDesktop) {
                if (widgetRegions.length > 0)
                    return compositeWidgetMask;
                return emptyRegion;
            }
            return null;
        }
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        Region {
            id: emptyRegion

            width: 0
            height: 0
        }
        Region {
            id: compositeWidgetMask

            regions: win.widgetRegions
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            enabled: !Config.background.disableQuickshellDesktop
            onTapped: (eventPoint, button) => {
                if (Config.background.disableQuickshellDesktop)
                    return;
                if (desktopIcons.renameActive)
                    desktopIcons.renamingDelegate?.commitRename();
                const onEmptyDesktop = !desktopIcons.iconAt(eventPoint.position.x, eventPoint.position.y) && !ContextMenuStore.editMode;
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
                active: Config.background.wallpaperEnabled && !ContextMenuStore.editMode && !Config.background.disableQuickshellDesktop
                visible: !ContextMenuStore.editMode
                sourceComponent: Wallpaper {
                    screen: win.modelData
                }
            }
        }
        DesktopIcons {
            id: desktopIcons

            screenData: win.modelData
            wallpaper: behindClock
            z: 3
        }
        Repeater {
            id: bgWidgetsRepeater

            model: BackgroundWidgetRegistry.widgetList

            Loader {
                id: bgWidgetLoader

                required property var modelData

                readonly property int revision: BackgroundWidgetRegistry.revision

                anchors.fill: parent
                z: modelData.z ?? 4
                source: modelData.componentUrl ?? ""

                onItemChanged: {
                    win.applyWidgetContext(item);
                    win.widgetUpdateTrigger++;
                }
                onRevisionChanged: {
                    // Widgets read their settings once, when they are created: reload the
                    // component so a change made in Nexus takes effect without a restart.
                    active = false;
                    Qt.callLater(() => {
                        active = true;
                    });
                }
            }
        }
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: (!Config.background.disableQuickshellDesktop && desktopIcons.renameActive) ? WlrKeyboardFocus.Exclusive : (!Config.background.disableQuickshellDesktop && desktopIcons.visible) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    }
}
