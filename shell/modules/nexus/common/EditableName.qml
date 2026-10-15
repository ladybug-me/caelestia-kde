pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

Item {
    id: root

    property string label
    property string subtext
    property string placeholder
    property bool overridden
    property bool editing: false

    signal renamed(string name)

    function startEdit(): void {
        field.text = root.overridden ? root.label : "";
        root.editing = true;
        field.forceActiveFocus();
        field.selectAll();
    }

    function commit(): void {
        if (!root.editing)
            return;
        root.editing = false;
        root.renamed(field.text.trim());
    }

    function cancel(): void {
        root.editing = false;
    }

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column

        anchors.fill: parent
        spacing: 0

        StyledText {
            id: labelText

            Layout.fillWidth: true
            visible: !root.editing
            text: root.label
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.editing && !!root.subtext
            text: root.subtext
            color: Colours.palette.m3onSurfaceVariant
            font: NexusStyle.secondaryFont
            elide: Text.ElideRight
        }

        StyledTextField {
            id: field

            Layout.fillWidth: true
            Layout.minimumWidth: 160
            visible: root.editing
            horizontalAlignment: TextInput.AlignLeft
            verticalPadding: Tokens.padding.small
            horizontalPadding: Tokens.padding.medium
            placeholderText: root.placeholder
            onAccepted: root.commit()
            onActiveFocusChanged: {
                if (!activeFocus && root.editing)
                    root.commit();
            }
            Keys.onEscapePressed: root.cancel()

            Connections {
                function onActiveChanged(): void {
                    if (field.Window.window.active)
                        field.forceActiveFocus();
                }

                target: field.Window.window
                enabled: root.editing
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.editing
        cursorShape: Qt.IBeamCursor
        onClicked: root.startEdit()
    }
}
