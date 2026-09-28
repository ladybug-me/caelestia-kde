pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls as Controls
import qs.components.effects
import qs.services

Popup {
    id: root

    property string shortcutName: ""
    property string currentKey: ""
    property string capturedKey: ""
    property var targetItem: null

    signal confirm(string name, string newKey)
    signal clear(string name)
    signal unblocked()

    width: 320
    padding: 24
    height: contentColumn.implicitHeight + 48

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    parent: Overlay.overlay

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Tokens.anim.durations.small }
        NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: Tokens.anim.durations.small; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Tokens.anim.durations.small }
        NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: Tokens.anim.durations.small; easing.type: Easing.InCubic }
    }

    x: targetItem && parent ? Math.min(parent.width - width - 16, Math.max(16, targetItem.mapToItem(parent, targetItem.width - width, targetItem.height + 8).x)) : (parent ? Math.round((parent.width - width) / 2) : 0)
    y: targetItem && parent ? Math.min(parent.height - height - 16, Math.max(16, targetItem.mapToItem(parent, 0, targetItem.height + 8).y)) : (parent ? Math.round((parent.height - height) / 2) : 0)

    background: Item {
        Elevation {
            anchors.fill: bgRect
            level: 3
            radius: bgRect.radius
        }
        Rectangle {
            id: bgRect

            anchors.fill: parent
            color: Colours.palette.m3surfaceContainerHigh
            radius: 16
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
        }
    }

    onVisibleChanged: {
        if (visible) {
            focusTimer.start()
        }
    }

    onOpened: {
        capturedKey = ""
        blockShortcutsProc.running = true
    }

    onClosed: {
        unblockShortcutsProc.running = true
    }

    contentItem: ColumnLayout {
        id: contentColumn

        spacing: 16

        StyledText {
            text: qsTr("Record Keybind")
            font: Tokens.font.title.medium
            color: Colours.palette.m3onSurface
            Layout.fillWidth: true
        }

        FocusScope {
            id: focusScope

            Layout.fillWidth: true
            Layout.preferredHeight: 64

            Keys.onPressed: (event) => {
                let modifiers = ""
                if (event.modifiers & Qt.MetaModifier) modifiers += "Meta+"
                if (event.modifiers & Qt.ControlModifier) modifiers += "Ctrl+"
                if (event.modifiers & Qt.AltModifier) modifiers += "Alt+"
                if (event.modifiers & Qt.ShiftModifier) modifiers += "Shift+"

                let keyStr = ""
                if (event.key !== Qt.Key_Meta && event.key !== Qt.Key_Control && 
                    event.key !== Qt.Key_Alt && event.key !== Qt.Key_Shift && 
                    event.key !== Qt.Key_Super_L && event.key !== Qt.Key_Super_R) {
                    
                    if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                        keyStr = String.fromCharCode(event.key)
                    } else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                        keyStr = String.fromCharCode(event.key)
                    } else if (event.key === Qt.Key_Space) {
                        keyStr = "Space"
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        keyStr = "Return"
                    } else if (event.key === Qt.Key_Escape) {
                        keyStr = "Escape"
                    } else if (event.key === Qt.Key_Tab) {
                        keyStr = "Tab"
                    } else if (event.key === Qt.Key_Up) {
                        keyStr = "Up"
                    } else if (event.key === Qt.Key_Down) {
                        keyStr = "Down"
                    } else if (event.key === Qt.Key_Left) {
                        keyStr = "Left"
                    } else if (event.key === Qt.Key_Right) {
                        keyStr = "Right"
                    } else if (event.key === Qt.Key_Print || event.key === Qt.Key_SysReq) {
                        keyStr = "Print"
                    } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35) {
                        keyStr = "F" + (event.key - Qt.Key_F1 + 1)
                    } else {
                        // Fallback (e.g. F-keys)
                        // Note: QKeySequence string conversion isn't directly exposed to JS, 
                        // so we handle common ones. Others might be obscure.
                        keyStr = String.fromCharCode(event.key)
                    }
                    root.capturedKey = modifiers + keyStr
                }
                event.accepted = true
            }

            Rectangle {
                anchors.fill: parent
                color: focusScope.activeFocus ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceVariant
                radius: Tokens.rounding.medium
                border.width: focusScope.activeFocus ? 2 : 1
                border.color: focusScope.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outline

                StyledText {
                    anchors.centerIn: parent
                    text: root.capturedKey === "" ? qsTr("Press keys now...") : root.capturedKey
                    font: Tokens.font.body.large
                    color: focusScope.activeFocus ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8

            Controls.TextButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            Item { Layout.fillWidth: true }

            Controls.TextButton {
                text: qsTr("Confirm")
                enabled: root.capturedKey !== ""
                onClicked: {
                    let finalKey = root.capturedKey
                    if (root.targetItem && root.currentKey !== "") {
                        finalKey = root.currentKey + "; " + root.capturedKey
                    }
                    root.confirm(root.shortcutName, finalKey)
                    root.close()
                }
            }
        }
    }

    Timer {
        id: focusTimer

        interval: 10
        onTriggered: focusScope.forceActiveFocus()
    }

    Process {
        id: blockShortcutsProc

        command: ["bash", "-c", "gdbus call --session --dest=org.kde.kglobalaccel --object-path=/kglobalaccel --method=org.kde.KGlobalAccel.blockGlobalShortcuts 'true'"]
    }

    Process {
        id: unblockShortcutsProc

        command: ["bash", "-c", "gdbus call --session --dest=org.kde.kglobalaccel --object-path=/kglobalaccel --method=org.kde.KGlobalAccel.blockGlobalShortcuts 'false'"]
        onExited: {
            root.unblocked()
        }
    }
}
