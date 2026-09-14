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
        // The fallback black waits for the wallpaper to have something to show, so a
        // starting shell does not cover the desktop in black while the image is still
        // decoding. It latches: readiness comes from an image decode status and from
        // video playback, and letting it flip would blink the whole desktop surface
        // between black and transparent for as long as the state kept changing.
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
        // If Quickshell wallpaper is disabled, use empty mask so KDE desktop gets clicks
        // If enabled, use null mask so Quickshell captures clicks
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
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (eventPoint, button) => {
                if (button === Qt.RightButton && Config.background.wallpaperEnabled) {
                    ContextMenuStore.openDesktopContextMenu(eventPoint.position.x, eventPoint.position.y, win.modelData.name);
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
            screenData: win.modelData
            z: 3
        }
        Loader {
            id: clockLoader

            readonly property int clockBarZone: Visibilities.bars.get(win.modelData.name)?.visualThickness ?? (Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness))
            readonly property int clockBaseMargin: Tokens.padding.extraLargeIncreased

            asynchronous: true
            active: Config.background.desktopClock.enabled
            anchors.margins: clockBaseMargin
            anchors.leftMargin: Config.bar.position === "left" ? clockBaseMargin + clockBarZone : clockBaseMargin
            anchors.rightMargin: Config.bar.position === "right" ? clockBaseMargin + clockBarZone : clockBaseMargin
            anchors.topMargin: Config.bar.position === "top" ? clockBaseMargin + clockBarZone : clockBaseMargin
            anchors.bottomMargin: Config.bar.position === "bottom" ? clockBaseMargin + clockBarZone : clockBaseMargin
            anchors.horizontalCenterOffset: {
                if (Config.bar.position === "left") return clockBarZone / 2;
                if (Config.bar.position === "right") return -clockBarZone / 2;
                return 0;
            }
            anchors.verticalCenterOffset: {
                if (Config.bar.position === "top") return clockBarZone / 2;
                if (Config.bar.position === "bottom") return -clockBarZone / 2;
                return 0;
            }
            sourceComponent: DesktopClock {
                wallpaper: behindClock
                absX: clockLoader.x
                absY: clockLoader.y
            }
            transitions: Transition {
                AnchorAnim {}
            }
            state: Config.background.desktopClock.position
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]
        }
        Loader {
            id: lyricsLoader

            readonly property int lyricsBarZone: Visibilities.bars.get(win.modelData.name)?.visualThickness ?? (Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness))
            readonly property int lyricsBaseMargin: Tokens.padding.large * 2

            asynchronous: true
            active: Config.background.desktopLyrics.enabled && !(GameMode.enabled && GlobalConfig.utilities.gameMode.disableDesktopLyrics)
            anchors.margins: lyricsBaseMargin
            anchors.leftMargin: Config.bar.position === "left" ? lyricsBaseMargin + lyricsBarZone : lyricsBaseMargin
            anchors.rightMargin: Config.bar.position === "right" ? lyricsBaseMargin + lyricsBarZone : lyricsBaseMargin
            anchors.topMargin: Config.bar.position === "top" ? lyricsBaseMargin + lyricsBarZone : lyricsBaseMargin
            anchors.bottomMargin: Config.bar.position === "bottom" ? lyricsBaseMargin + lyricsBarZone : lyricsBaseMargin
            anchors.horizontalCenterOffset: {
                if (Config.bar.position === "left") return lyricsBarZone / 2;
                if (Config.bar.position === "right") return -lyricsBarZone / 2;
                return 0;
            }
            anchors.verticalCenterOffset: {
                if (Config.bar.position === "top") return lyricsBarZone / 2;
                if (Config.bar.position === "bottom") return -lyricsBarZone / 2;
                return 0;
            }
            sourceComponent: DesktopLyrics {
                screen: modelData
                wallpaper: behindClock
                absX: lyricsLoader.x
                absY: lyricsLoader.y
            }
            transitions: Transition {
                AnchorAnim {}
            }
            state: Config.background.desktopLyrics.position
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "center"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: lyricsLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]
        }
        Loader {
            id: shapesLoader

            readonly property int shapesBarZone: Visibilities.bars.get(win.modelData.name)?.visualThickness ?? (Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness))
            readonly property int shapesBaseMargin: Tokens.padding.large * 2

            asynchronous: true
            active: Config.background.desktopShapes.enabled && !(GameMode.enabled && GlobalConfig.utilities.gameMode.disableDesktopLyrics)
            anchors.margins: shapesBaseMargin
            anchors.leftMargin: Config.bar.position === "left" ? shapesBaseMargin + shapesBarZone : shapesBaseMargin
            anchors.rightMargin: Config.bar.position === "right" ? shapesBaseMargin + shapesBarZone : shapesBaseMargin
            anchors.topMargin: Config.bar.position === "top" ? shapesBaseMargin + shapesBarZone : shapesBaseMargin
            anchors.bottomMargin: Config.bar.position === "bottom" ? shapesBaseMargin + shapesBarZone : shapesBaseMargin
            anchors.horizontalCenterOffset: {
                if (Config.bar.position === "left") return shapesBarZone / 2;
                if (Config.bar.position === "right") return -shapesBarZone / 2;
                return 0;
            }
            anchors.verticalCenterOffset: {
                if (Config.bar.position === "top") return shapesBarZone / 2;
                if (Config.bar.position === "bottom") return -shapesBarZone / 2;
                return 0;
            }
            sourceComponent: DesktopShapes {
                screen: modelData
                wallpaper: behindClock
                absX: shapesLoader.x
                absY: shapesLoader.y
            }
            transitions: Transition {
                AnchorAnim {}
            }
            state: Config.background.desktopShapes.position
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "center"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: shapesLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]
        }
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
    }
}
