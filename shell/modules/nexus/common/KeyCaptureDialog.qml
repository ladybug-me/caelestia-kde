pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Services
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
    property real popupX: 0
    property real popupY: 0
    property bool isClosing: false
    property bool escHolding: false
    property real escHoldProgress: 0
    property string escHeldMods: ""
    property bool enterHolding: false
    property real enterHoldProgress: 0
    property string enterHeldMods: ""
    readonly property var conflictInfo: {
        if (capturedKey === "")
            return null;
        const all = KeybindsModel.query("");
        for (let i = 0; i < all.length; i++) {
            if (all[i].name === shortcutName)
                continue;
            const parts = String(all[i].bind || "").split(";");
            for (let j = 0; j < parts.length; j++) {
                if (parts[j].trim() === capturedKey)
                    return {
                        name: all[i].name,
                        label: all[i].description || all[i].name
                    };
            }
        }
        const stolen = KeybindsModel.getKeyCollisionForPart(shortcutName, capturedKey);
        if (stolen !== "")
            return {
                name: "",
                label: stolen
            };
        return null;
    }
    readonly property string conflict: root.conflictInfo ? root.conflictInfo.name : ""
    readonly property string conflictLabel: root.conflictInfo ? root.conflictInfo.label : ""

    signal confirm(string name, string newKey)
    signal clear(string name)
    signal unblocked()

    function confirmAndClose(): void {
        if (root.capturedKey === "")
            return;
        let finalKey = root.capturedKey;
        if (root.targetItem && root.currentKey !== "") {
            finalKey = root.currentKey + "; " + root.capturedKey;
        }
        if (root.conflict !== "") {
            const otherKey = KeybindsModel.getKey(root.conflict);
            if (otherKey !== "") {
                const parts = otherKey.split(";").map(s => s.trim()).filter(s => s.length > 0 && s !== root.capturedKey);
                KeybindsModel.setKey(root.conflict, parts.join("; "));
            }
        }
        root.isClosing = true;
        root.close();
        root.confirm(root.shortcutName, finalKey);
    }

    function updatePosition(): void {
        if (!parent || root.isClosing)
            return;
        if (targetItem) {
            root.popupX = Math.min(parent.width - width - 16, Math.max(16, targetItem.mapToItem(parent, targetItem.width - width, targetItem.height + 8).x));
            root.popupY = Math.min(parent.height - height - 16, Math.max(16, targetItem.mapToItem(parent, 0, targetItem.height + 8).y));
        } else {
            root.popupX = Math.round((parent.width - width) / 2);
            root.popupY = Math.round((parent.height - height) / 2);
        }
    }

    x: root.popupX
    y: root.popupY
    width: 300
    padding: 16
    height: contentColumn.implicitHeight + 28

    modal: true
    focus: true
    closePolicy: Popup.CloseOnPressOutside
    parent: Overlay.overlay

    enter: DialogTransition { }
    exit: DialogTransition {
        exiting: true
    }

    onAboutToShow: {
        root.isClosing = false;
        updatePosition();
    }
    onAboutToHide: {
        root.isClosing = true;
    }

    onTargetItemChanged: updatePosition()
    onHeightChanged: updatePosition()
    onWidthChanged: updatePosition()

    onConflictChanged: {
        // The error text below is what names the conflict; the shake only drives it home.
        if (root.conflict !== "" && Tokens.anim.enabled)
            shakeAnim.start();
    }

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
            radius: Tokens.rounding.large
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
        root.isClosing = false;
        updatePosition();
        capturedKey = "";
        escHoldAnim.stop();
        enterHoldAnim.stop();
        root.escHolding = false;
        root.escHoldProgress = 0;
        root.escHeldMods = "";
        root.enterHolding = false;
        root.enterHoldProgress = 0;
        root.enterHeldMods = "";
        blockShortcutsProc.running = true;
    }

    onClosed: {
        root.isClosing = false;
        escHoldAnim.stop();
        enterHoldAnim.stop();
        root.escHolding = false;
        root.escHoldProgress = 0;
        root.escHeldMods = "";
        root.enterHolding = false;
        root.enterHoldProgress = 0;
        root.enterHeldMods = "";
        unblockShortcutsProc.running = true;
    }

    Component.onDestruction: {
        Quickshell.execDetached(["bash", "-c", "gdbus call --session --dest=org.kde.kglobalaccel --object-path=/kglobalaccel --method=org.kde.KGlobalAccel.blockGlobalShortcuts 'false'"]);
    }

    contentItem: ColumnLayout {
        id: contentColumn

        spacing: 8

        transform: Translate {
            id: shakeTr
        }

        StyledText {
            text: qsTr("Record Keybind")
            font: Tokens.font.title.medium
            color: Colours.palette.m3onSurface
            Layout.fillWidth: true
        }

        FocusScope {
            id: focusScope

            Layout.fillWidth: true
            Layout.preferredHeight: 40

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    if (root.enterHolding) {
                        enterHoldAnim.stop()
                        root.enterHolding = false
                        root.enterHoldProgress = 0
                    }
                    if (!event.isAutoRepeat) {
                        let modifiers = ""
                        if (event.modifiers & Qt.MetaModifier) modifiers += "Meta+"
                        if (event.modifiers & Qt.ControlModifier) modifiers += "Ctrl+"
                        if (event.modifiers & Qt.AltModifier) modifiers += "Alt+"
                        if (event.modifiers & Qt.ShiftModifier) modifiers += "Shift+"
                        root.escHeldMods = modifiers
                        root.escHolding = true
                        root.escHoldProgress = 0
                        escHoldAnim.restart()
                    }
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.escHolding) {
                        escHoldAnim.stop()
                        root.escHolding = false
                        root.escHoldProgress = 0
                    }
                    if (!event.isAutoRepeat) {
                        let modifiers = ""
                        if (event.modifiers & Qt.MetaModifier) modifiers += "Meta+"
                        if (event.modifiers & Qt.ControlModifier) modifiers += "Ctrl+"
                        if (event.modifiers & Qt.AltModifier) modifiers += "Alt+"
                        if (event.modifiers & Qt.ShiftModifier) modifiers += "Shift+"
                        root.enterHeldMods = modifiers
                        root.enterHolding = true
                        root.enterHoldProgress = 0
                        enterHoldAnim.restart()
                    }
                    event.accepted = true
                    return
                } else {
                    if (root.escHolding) {
                        escHoldAnim.stop()
                        root.escHolding = false
                        root.escHoldProgress = 0
                    }
                    if (root.enterHolding) {
                        enterHoldAnim.stop()
                        root.enterHolding = false
                        root.enterHoldProgress = 0
                    }
                }

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
                        keyStr = String.fromCharCode(event.key)
                    }
                    let mods = modifiers
                    if (mods.indexOf("Shift") >= 0 && keyStr.length === 1 && !/[A-Za-z0-9]/.test(keyStr))
                        mods = mods.replace("Shift+", "")
                    root.capturedKey = mods + keyStr
                }
                event.accepted = true
            }

            Keys.onReleased: (event) => {
                if (event.key === Qt.Key_Escape) {
                    if (!event.isAutoRepeat) {
                        if (root.escHolding) {
                            escHoldAnim.stop()
                            root.escHolding = false
                            root.escHoldProgress = 0
                            root.capturedKey = root.escHeldMods + "Escape"
                        }
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (!event.isAutoRepeat) {
                        if (root.enterHolding) {
                            enterHoldAnim.stop()
                            root.enterHolding = false
                            root.enterHoldProgress = 0
                            root.capturedKey = root.enterHeldMods + "Return"
                        }
                    }
                    event.accepted = true
                }
            }

            Rectangle {
                anchors.fill: parent
                color: focusScope.activeFocus ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceVariant
                radius: Tokens.rounding.medium
                border.width: focusScope.activeFocus ? 2 : 1
                border.color: focusScope.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outline

                StyledText {
                    anchors.centerIn: parent
                    visible: root.capturedKey === ""
                    text: qsTr("Press keys now...")
                    font: Tokens.font.body.large
                    color: focusScope.activeFocus ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    anchors.centerIn: parent
                    visible: root.capturedKey !== ""
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: root.capturedKey === "" ? [] : root.capturedKey.split("+")

                        RowLayout {
                            required property string modelData
                            required property int index

                            spacing: Tokens.spacing.extraSmall

                            StyledText {
                                visible: index > 0
                                text: "+"
                                font: Tokens.font.body.large
                                color: focusScope.activeFocus ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            }

                            StyledRect {
                                radius: Tokens.rounding.small
                                color: focusScope.activeFocus ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
                                implicitWidth: capLabel.implicitWidth + Tokens.padding.medium * 2
                                implicitHeight: capLabel.implicitHeight + Tokens.padding.small * 2

                                StyledText {
                                    id: capLabel

                                    anchors.centerIn: parent
                                    text: modelData
                                    font: Tokens.font.body.medium
                                    color: focusScope.activeFocus ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            visible: root.escHolding

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "cancel"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3error
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Hold Escape to cancel (%1s)").arg((1.5 * (1 - root.escHoldProgress)).toFixed(1))
                    color: Colours.palette.m3error
                    font: NexusStyle.secondaryFont
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 3
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceVariant
                clip: true

                Rectangle {
                    width: parent.width * root.escHoldProgress
                    height: parent.height
                    radius: parent.radius
                    color: Colours.palette.m3error
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            visible: root.enterHolding

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "check_circle"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Hold Enter to accept shortcut (%1s)").arg((1.5 * (1 - root.enterHoldProgress)).toFixed(1))
                    color: Colours.palette.m3primary
                    font: NexusStyle.secondaryFont
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 3
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceVariant
                clip: true

                Rectangle {
                    width: parent.width * root.enterHoldProgress
                    height: parent.height
                    radius: parent.radius
                    color: Colours.palette.m3primary
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.conflict !== ""
            text: qsTr("Already used by %1").arg(root.conflictLabel)
            color: Colours.palette.m3error
            font: NexusStyle.secondaryFont
            elide: Text.ElideRight
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
                text: root.conflict !== "" ? qsTr("Replace") : qsTr("Confirm")
                enabled: root.capturedKey !== ""
                onClicked: root.confirmAndClose()
            }
        }
    }

    SequentialAnimation {
        id: shakeAnim

        NumberAnimation {
            target: shakeTr
            property: "x"
            to: -8
            duration: 50
        }
        NumberAnimation {
            target: shakeTr
            property: "x"
            to: 8
            duration: 50
        }
        NumberAnimation {
            target: shakeTr
            property: "x"
            to: -5
            duration: 50
        }
        NumberAnimation {
            target: shakeTr
            property: "x"
            to: 5
            duration: 50
        }
        NumberAnimation {
            target: shakeTr
            property: "x"
            to: 0
            duration: 50
        }
    }

    NumberAnimation {
        id: escHoldAnim

        target: root
        property: "escHoldProgress"
        from: 0
        to: 1
        duration: 1500
        onFinished: {
            root.escHolding = false
            root.escHoldProgress = 0
            root.capturedKey = ""
            root.close()
        }
    }

    NumberAnimation {
        id: enterHoldAnim

        target: root
        property: "enterHoldProgress"
        from: 0
        to: 1
        duration: 1500
        onFinished: {
            root.enterHolding = false
            root.enterHoldProgress = 0
            if (root.capturedKey === "") {
                root.capturedKey = root.enterHeldMods + "Return"
            }
            root.confirmAndClose()
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
