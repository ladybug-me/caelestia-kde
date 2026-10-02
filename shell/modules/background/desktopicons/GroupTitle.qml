import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Name of an open group; click it to rename the group in place.
Item {
    id: root

    property string text
    property bool renaming: false

    signal renameRequested
    signal renameCommitted(string text)
    signal renameCancelled

    function startRename(current: string): void {
        renaming = true;
        field.text = current;
        field.selectAll();
        field.forceActiveFocus();
    }

    function commitRename(): void {
        if (!renaming)
            return;
        renaming = false;
        renameCommitted(field.text);
    }

    function cancelRename(): void {
        if (!renaming)
            return;
        renaming = false;
        renameCancelled();
    }

    implicitHeight: Math.max(label.implicitHeight, field.implicitHeight)
    height: implicitHeight

    StyledText {
        id: label

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, parent.width)
        visible: !root.renaming
        text: root.text
        font: Tokens.font.title.medium
        elide: Text.ElideRight

        MouseArea {
            anchors.fill: parent
            anchors.margins: -Tokens.padding.small
            cursorShape: Qt.IBeamCursor
            onClicked: root.renameRequested()
        }
    }

    StyledTextField {
        id: field

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.renaming
        horizontalAlignment: TextInput.AlignHCenter
        onAccepted: root.commitRename()
        onActiveFocusChanged: {
            if (!activeFocus && root.renaming)
                root.commitRename();
        }
        Keys.onEscapePressed: root.cancelRename()

        // Focus once the compositor hands the window the keyboard, as for icon renames.
        Connections {
            function onActiveChanged(): void {
                if (field.Window.window.active)
                    field.forceActiveFocus();
            }

            target: field.Window.window
            enabled: root.renaming
        }
    }
}
