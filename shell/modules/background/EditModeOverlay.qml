pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// The pill that says which edit mode the desktop is in and offers its way out.
// The two modes exclude each other, so one surface carries both; a second overlay
// would only repeat this window, its mask and its placement.
Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData
        readonly property var controller: DesktopLayout.controllerFor(win.modelData.name)
        readonly property bool plasma: ContextMenuStore.editMode
        readonly property bool widgets: WidgetEditor.active && win.controller !== null
        readonly property bool shouldShow: win.plasma || win.widgets
        readonly property int barZone: Visibilities.bars.get(win.modelData.name)?.visualThickness ?? (Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness))
        readonly property int topMargin: Config.bar.position === "top" ? Tokens.spacing.large + barZone : Tokens.spacing.large

        screen: modelData
        Tokens.screen: modelData.name
        Config.screen: modelData.name
        name: "edit-mode-overlay"
        WlrLayershell.namespace: "overlay"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        visible: win.shouldShow || pill.opacity > 0.01
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        mask: win.shouldShow ? pillRegion : emptyRegion

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
            color: Colours.palette.m3surfaceContainerHigh
            border.width: Math.max(1, Config.border.thickness)
            border.color: Colours.palette.m3outlineVariant

            Elevation {
                anchors.fill: parent
                radius: parent.radius
                opacity: parent.opacity
                z: -1
                level: 3
            }

            // The Plasma pill is its own button; the widget pill is a row of them,
            // so only the Plasma mode takes a click on the pill's background. Kept
            // under the row, so the buttons always win where they overlap.
            StateLayer {
                enabled: win.plasma
                radius: parent.radius
                onClicked: ContextMenuStore.editMode = false
            }

            RowLayout {
                id: row

                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    visible: win.plasma
                    text: "close"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.title.small
                }

                StyledText {
                    visible: win.plasma
                    text: qsTr("Exit Plasma edit mode")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurface
                }

                MaterialIcon {
                    visible: win.widgets
                    text: "widgets"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.title.small
                }

                StyledText {
                    visible: win.widgets
                    text: qsTr("Editing widgets")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onSurface
                }

                StyledRect {
                    visible: win.widgets
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: Tokens.padding.large
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: Tokens.spacing.small
                    Layout.rightMargin: Tokens.spacing.small
                    color: Qt.alpha(Colours.palette.m3outline, 0.4)
                }

                IconTextButton {
                    visible: win.widgets
                    type: IconTextButton.Text
                    icon: "add"
                    text: qsTr("Add widget")
                    onClicked: win.controller.requestWidgetGallery()
                }

                IconTextButton {
                    visible: win.widgets
                    type: IconTextButton.Text
                    icon: DesktopLayout.anyWidgetUnlocked() ? "lock_open" : "lock"
                    text: DesktopLayout.anyWidgetUnlocked() ? qsTr("Lock all") : qsTr("Unlock all")
                    onClicked: DesktopLayout.setAllWidgetsLocked(DesktopLayout.anyWidgetUnlocked())
                }

                TextButton {
                    visible: win.widgets
                    type: TextButton.Filled
                    text: qsTr("Done")
                    onClicked: WidgetEditor.close()
                }
            }

            // The Plasma pill is its own button; the widget pill is a row of them,
            // so only the Plasma mode takes a click on the pill's background.
            StateLayer {
                enabled: win.plasma
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
