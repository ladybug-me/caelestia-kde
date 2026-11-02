pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services
import qs.modules.nexus.common

ConnectedRect {
    id: root

    property alias label: label.text
    property alias status: status.text
    property string actionName: ""
    property string keybind: ""
    property bool isOverridden: false
    property bool isShell: false

    readonly property var keyParts: {
        return root.keybind.split(";").map(s => s.trim()).filter(s => s.length > 0)
    }
    property int subIndex: keyParts.length

    signal clicked
    signal addClicked(var target)
    signal resetClicked
    signal keybindEdited(string newKeybind)

    function removeKeyPart(idx: int): void {
        let parts = [...keyParts]
        if (idx >= 0 && idx < parts.length) {
            parts.splice(idx, 1)
            root.keybindEdited(parts.join("; "))
            if (subIndex >= parts.length)
                subIndex = Math.max(0, parts.length)
        }
    }

    function activate(): void {
        const parts = keyParts
        const addIdx = parts.length
        const resetIdx = parts.length + 1

        if (subIndex === resetIdx && root.isOverridden) {
            root.resetClicked()
        } else if (subIndex >= 0 && subIndex < parts.length) {
            removeKeyPart(subIndex)
        } else {
            root.addClicked(addIcon)
        }
    }

    function stepLeft(): bool {
        const parts = keyParts
        const resetIdx = parts.length + 1
        const addIdx = parts.length

        if (subIndex === resetIdx) {
            subIndex = addIdx
            return true
        } else if (subIndex === addIdx) {
            if (parts.length > 0) {
                subIndex = parts.length - 1
                return true
            }
            return false
        } else if (subIndex > 0) {
            subIndex--
            return true
        }
        return false
    }

    function stepRight(): bool {
        const parts = keyParts
        const resetIdx = parts.length + 1
        const addIdx = parts.length

        if (subIndex < parts.length - 1) {
            subIndex++
            return true
        } else if (subIndex === parts.length - 1) {
            subIndex = addIdx
            return true
        } else if (subIndex === addIdx && root.isOverridden) {
            subIndex = resetIdx
            return true
        }
        return true
    }

    function handleDelete(): bool {
        const parts = keyParts
        if (subIndex >= 0 && subIndex < parts.length) {
            removeKeyPart(subIndex)
            return true
        } else if (subIndex === parts.length + 1 && root.isOverridden) {
            root.resetClicked()
            return true
        } else if (root.isOverridden) {
            root.resetClicked()
            return true
        } else if (parts.length > 0) {
            removeKeyPart(parts.length - 1)
            return true
        }
        return false
    }

    function handleEscape(): bool {
        if (subIndex !== keyParts.length) {
            subIndex = keyParts.length
            return true
        }
        return false
    }

    onIsSelectedChanged: {
        if (isSelected) {
            subIndex = keyParts.length
        }
    }

    onKeybindChanged: {
        if (subIndex > keyParts.length + (root.isOverridden ? 1 : 0)) {
            subIndex = keyParts.length
        }
    }

    onClicked: root.activate()

    Layout.fillWidth: true
    implicitHeight: navLayout.implicitHeight + navLayout.anchors.margins * 2

    StateLayer {
        anchors.fill: parent
        manualHoverOverride: root.isSelected
        onClicked: root.clicked()
    }

    RowLayout {
        id: navLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: label
                Layout.fillWidth: true

                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                id: status
                Layout.fillWidth: true

                visible: text
                color: Colours.palette.m3onSurfaceVariant
                font: NexusStyle.secondaryFont
                elide: Text.ElideRight
                animate: true
            }
        }

        RowLayout {
            spacing: Tokens.spacing.small

            Repeater {
                model: root.keyParts
                delegate: Rectangle {
                    id: pillDelegate

                    required property string modelData
                    required property int index

                    readonly property bool isSubFocused: root.isSelected && root.subIndex === index

                    Layout.preferredHeight: 32
                    Layout.preferredWidth: pillRow.implicitWidth + Tokens.padding.medium * 2
                    radius: Tokens.rounding.small
                    color: isSubFocused ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh
                    border.width: isSubFocused ? 2 : 1
                    border.color: isSubFocused ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                    RowLayout {
                        id: pillRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            text: pillDelegate.modelData
                            font: Tokens.font.label.medium
                            color: pillDelegate.isSubFocused ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        }

                        Rectangle {
                            property string partCollisionName: KeybindsModel.getKeyCollisionForPart(root.actionName, pillDelegate.modelData)

                            visible: partCollisionName !== ""
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            Layout.alignment: Qt.AlignVCenter
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3error

                            layer.enabled: true

                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Colours.palette.m3error
                                shadowBlur: 0.8
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                ToolTip.visible: containsMouse
                                ToolTip.text: qsTr("Collides with: ") + parent.partCollisionName
                            }
                        }

                        MaterialIcon {
                            text: "close"
                            fontStyle: Tokens.font.icon.small
                            color: (pillDelegate.isSubFocused || maClose.containsMouse) ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant

                            MouseArea {
                                id: maClose

                                anchors.fill: parent
                                anchors.margins: -Tokens.padding.small
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeKeyPart(pillDelegate.index)
                            }

                            Behavior on color {
                                CAnim {}
                            }
                        }
                    }

                    Behavior on color {
                        CAnim {}
                    }
                    Behavior on border.color {
                        CAnim {}
                    }
                }
            }

            Rectangle {
                id: addBtn

                readonly property bool isAddFocused: root.isSelected && root.subIndex === root.keyParts.length

                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: Tokens.rounding.small
                color: isAddFocused ? Colours.palette.m3secondaryContainer : (maAdd.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent")
                border.width: isAddFocused ? 2 : 0
                border.color: Colours.palette.m3primary

                MaterialIcon {
                    id: addIcon

                    anchors.centerIn: parent
                    text: "add"
                    color: (addBtn.isAddFocused || maAdd.containsMouse) ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                MouseArea {
                    id: maAdd

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.subIndex = root.keyParts.length
                        root.addClicked(addIcon)
                    }
                }

                Behavior on color {
                    CAnim {}
                }
            }

            Rectangle {
                id: resetBtn

                readonly property bool isResetFocused: root.isSelected && root.subIndex === root.keyParts.length + 1

                visible: root.isOverridden
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: Tokens.rounding.small
                color: isResetFocused ? Colours.layer(Colours.palette.m3errorContainer, 2) : (maReset.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent")
                border.width: isResetFocused ? 2 : 0
                border.color: Colours.palette.m3error

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "settings_backup_restore"
                    color: (resetBtn.isResetFocused || maReset.containsMouse) ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                MouseArea {
                    id: maReset

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.subIndex = root.keyParts.length + 1
                        root.resetClicked()
                    }
                }

                Behavior on color {
                    CAnim {}
                }
            }
        }
    }
}
