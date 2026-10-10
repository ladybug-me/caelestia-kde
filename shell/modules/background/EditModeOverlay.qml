pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.effects
import qs.services

Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData
        readonly property int barZone: Visibilities.bars.get(win.modelData.name)?.visualThickness ?? (Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness))
        readonly property int topMargin: Config.bar.position === "top" ? Tokens.spacing.large + barZone : Tokens.spacing.large
        readonly property bool shouldShow: ContextMenuStore.editMode

        screen: modelData
        Tokens.screen: modelData.name
        Config.screen: modelData.name
        name: "edit-mode-overlay"
        WlrLayershell.namespace: "overlay"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        visible: shouldShow || pill.opacity > 0.01
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        mask: shouldShow ? pillRegion : emptyRegion

        BackgroundEffect.blurRegion: Region {
            Region {
                x: -10
                y: -10
                width: 1
                height: 1
            }
            Region {
                item: (GlobalConfig.appearance.transparency.enabled && GlobalConfig.appearance.blur && win.shouldShow) ? pill : null
            }
        }

        Region {
            id: pillRegion

            x: pill.x
            y: pill.y
            width: pill.width
            height: pill.height
        }

        Region {
            id: emptyRegion

            width: 0
            height: 0
        }

        StyledRect {
            id: pill

            y: win.shouldShow ? win.topMargin : (win.topMargin - 16)
            opacity: win.shouldShow ? 1 : 0
            scale: win.shouldShow ? 1 : 0.9

            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: row.implicitWidth + Tokens.padding.extraLarge * 2
            implicitHeight: row.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainerHigh
            border.width: Math.max(1, Config.border.thickness)
            border.color: Colours.palette.m3outlineVariant

            Elevation {
                anchors.fill: parent
                radius: parent.radius
                opacity: parent.opacity
                z: -1
                level: 3
            }

            RowLayout {
                id: row

                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "close"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.title.small
                }

                StyledText {
                    text: qsTr("Exit edit mode")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurface
                }
            }

            StateLayer {
                radius: parent.radius
                onClicked: ContextMenuStore.editMode = false
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            Behavior on y {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }
    }
}
