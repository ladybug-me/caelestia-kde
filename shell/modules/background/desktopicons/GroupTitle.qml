pragma ComponentBehavior: Bound

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
    // Drawn like a desktop icon label; renamed through F2 or the menu instead of a click.
    property bool desktopStyle: false

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

    implicitWidth: renaming ? 180 : label.implicitWidth
    implicitHeight: renaming ? field.implicitHeight : label.implicitHeight
    height: implicitHeight

    StyledText {
        id: label

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, parent.width)
        visible: !root.renaming
        text: root.text
        font: root.desktopStyle ? Tokens.font.body.small : Tokens.font.title.medium
        elide: Text.ElideRight
        style: root.desktopStyle ? Text.Outline : Text.Normal
        styleColor: Colours.palette.m3surface

        MouseArea {
            anchors.fill: parent
            enabled: !root.desktopStyle
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
        // On the desktop the editor has to fit the label row under the card.
        verticalPadding: root.desktopStyle ? Tokens.padding.small : Tokens.padding.large
        horizontalPadding: root.desktopStyle ? Tokens.padding.medium : Tokens.padding.large
        // On the desktop it stands in for the label, so no outline either.
        background.visible: !root.desktopStyle
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
