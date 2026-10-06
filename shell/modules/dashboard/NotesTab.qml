pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    property var notes: []
    property int selectedIndex: -1
    readonly property var selectedNote: root.selectedIndex >= 0 && root.selectedIndex < root.notes.length ? root.notes[root.selectedIndex] : null

    function newNote(): void {
        const note = {
            id: Date.now(),
            title: qsTr("Untitled"),
            body: "",
            updated: Date.now()
        };
        root.notes = [note, ...root.notes];
        root.selectedIndex = 0;
        saveTimer.restart();
    }

    function deleteNote(index: int): void {
        if (index < 0 || index >= root.notes.length)
            return;
        const arr = root.notes.slice();
        arr.splice(index, 1);
        root.notes = arr;
        root.selectedIndex = arr.length > 0 ? Math.min(index, arr.length - 1) : -1;
        saveTimer.restart();
    }

    function updateSelected(field: string, value: string): void {
        if (root.selectedIndex < 0)
            return;
        const arr = root.notes.slice();
        arr[root.selectedIndex] = Object.assign({}, arr[root.selectedIndex], {
            [field]: value,
            updated: Date.now()
        });
        root.notes = arr;
        saveTimer.restart();
    }

    implicitWidth: 840
    implicitHeight: 560
    Component.onCompleted: fileView.reload()

    FileView {
        id: fileView

        path: `${Paths.state}/notes_tab.json`
        watchChanges: false
        printErrors: false

        onLoaded: {
            try {
                const data = JSON.parse(fileView.text());
                if (Array.isArray(data))
                    root.notes = data;
            } catch (e) {
                root.notes = [];
            }
        }

        onLoadFailed: root.notes = []
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: {
            fileView.setText(JSON.stringify(root.notes));
        }
    }

    RowLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.preferredWidth: 260
            Layout.fillHeight: true

            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainerLow

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: qsTr("Notes")
                        font: Tokens.font.body.builders.large.size(20).weight(Font.DemiBold).build()
                        color: Colours.palette.m3onSurface
                        Layout.fillWidth: true
                    }

                    StyledRect {
                        id: newNoteBtn

                        implicitWidth: 34
                        implicitHeight: 34
                        radius: newNoteArea.pressed ? Tokens.rounding.medium : Tokens.rounding.full
                        color: newNoteArea.containsMouse ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
                        scale: newNoteArea.pressed ? 0.88 : 1

                        Behavior on radius {
                            Anim {
                                type: Anim.EmphasizedSmall
                            }
                        }

                        Behavior on scale {
                            Anim {
                                type: Anim.EmphasizedSmall
                            }
                        }

                        Behavior on color {
                            CAnim {}
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "add"
                            color: Colours.palette.m3onSecondaryContainer
                            fontStyle: Tokens.font.icon.medium
                        }

                        CustomMouseArea {
                            id: newNoteArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.newNote()
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Colours.palette.m3outlineVariant
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: list.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: list

                        width: parent.width
                        spacing: Tokens.spacing.extraSmall

                        Repeater {
                            model: root.notes

                            delegate: StyledRect {
                                id: noteItem

                                required property var modelData
                                required property int index

                                readonly property bool selected: index === root.selectedIndex

                                Layout.fillWidth: true
                                implicitHeight: itemCol.implicitHeight + Tokens.padding.medium

                                radius: selected ? Tokens.rounding.large : Tokens.rounding.medium
                                color: selected ? Colours.palette.m3secondaryContainer : (itemArea.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : "transparent")
                                scale: itemArea.pressed ? 0.97 : 1

                                Behavior on color {
                                    CAnim {}
                                }

                                Behavior on radius {
                                    Anim {
                                        type: Anim.EmphasizedSmall
                                    }
                                }

                                Behavior on scale {
                                    Anim {
                                        type: Anim.EmphasizedSmall
                                    }
                                }

                                ColumnLayout {
                                    id: itemCol

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Tokens.padding.small
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true

                                        StyledText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: noteItem.modelData.title || qsTr("Untitled")
                                            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                                            color: noteItem.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                                        }

                                        MaterialIcon {
                                            id: deleteIcon

                                            opacity: deleteArea.containsMouse || noteItem.selected ? 1 : 0
                                            scale: opacity === 1 ? 1 : 0.6
                                            text: "close"
                                            fontStyle: Tokens.font.icon.medium
                                            color: deleteArea.containsMouse ? Colours.palette.m3error : Colours.palette.m3onSecondaryContainer

                                            Behavior on opacity {
                                                Anim {
                                                    type: Anim.FastEffects
                                                }
                                            }

                                            Behavior on scale {
                                                Anim {
                                                    type: Anim.EmphasizedSmall
                                                }
                                            }

                                            Behavior on color {
                                                CAnim {}
                                            }

                                            CustomMouseArea {
                                                id: deleteArea

                                                anchors.fill: parent
                                                anchors.margins: -6
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.deleteNote(noteItem.index)
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        text: noteItem.modelData.body || qsTr("No additional text")
                                        font: Tokens.font.body.small
                                        opacity: 0.7
                                        color: noteItem.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                CustomMouseArea {
                                    id: itemArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    z: -1
                                    onClicked: root.selectedIndex = noteItem.index
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spacing.large
                            visible: root.notes.length === 0
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                Layout.alignment: Qt.AlignHCenter
                                text: "note_add"
                                fontStyle: Tokens.font.icon.extraLarge
                                color: Colours.palette.m3onSurfaceVariant
                                opacity: 0.4
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: qsTr("No notes yet. Tap + to add one.")
                                font: Tokens.font.body.small
                                opacity: 0.6
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true

            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainerLowest

            ColumnLayout {
                id: editorCol

                property var trackedId: root.selectedNote ? root.selectedNote.id : null

                onTrackedIdChanged: {
                    switchAnim.restart();
                }

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                visible: root.selectedNote !== null

                SequentialAnimation {
                    id: switchAnim

                    ParallelAnimation {
                        Anim {
                            target: editorCol
                            property: "opacity"
                            to: 0.35
                            type: Anim.FastEffects
                        }
                        Anim {
                            target: editorCol
                            property: "y"
                            to: 6
                            type: Anim.FastSpatial
                        }
                    }
                    ParallelAnimation {
                        Anim {
                            target: editorCol
                            property: "opacity"
                            to: 1
                            type: Anim.EmphasizedSmall
                        }
                        Anim {
                            target: editorCol
                            property: "y"
                            to: 0
                            type: Anim.EmphasizedSmall
                        }
                    }
                }

                StyledTextField {
                    id: titleField

                    Layout.fillWidth: true
                    type: StyledTextField.Filled
                    radius: Tokens.rounding.large
                    text: root.selectedNote ? root.selectedNote.title : ""
                    // The floating "Title" label only shows while the field is empty.
                    placeholderText: text.length === 0 ? qsTr("Title") : ""
                    font: Tokens.font.body.builders.large.size(22).weight(Font.DemiBold).build()
                    horizontalPadding: Tokens.padding.medium
                    verticalPadding: text.length === 0 ? Tokens.padding.large : Tokens.padding.medium
                    onTextEdited: root.updateSelected("title", text)

                    Keys.onReturnPressed: bodyField.forceActiveFocus()
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Colours.palette.m3outlineVariant
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: bodyField.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: bodyField

                        width: parent.width
                        text: root.selectedNote ? root.selectedNote.body : ""
                        wrapMode: TextEdit.Wrap
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        selectByMouse: true
                        selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                        selectedTextColor: color
                        renderType: TextEdit.NativeRendering
                        persistentSelection: true
                        onTextChanged: {
                            if (activeFocus)
                                root.updateSelected("body", text);
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            visible: bodyField.text.length === 0
                            text: qsTr("Start writing...")
                            font: bodyField.font
                            opacity: 0.5
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                StyledRect {
                    Layout.alignment: Qt.AlignRight
                    visible: root.selectedNote !== null
                    radius: Tokens.rounding.full
                    color: Colours.tPalette.m3surfaceContainerHigh
                    implicitWidth: editedLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: editedLabel.implicitHeight + Tokens.padding.small * 2

                    StyledText {
                        id: editedLabel

                        anchors.centerIn: parent
                        text: root.selectedNote ? qsTr("Edited %1").arg(new Date(root.selectedNote.updated).toLocaleTimeString(Qt.locale(), "hh:mm")) : ""
                        font: Tokens.font.body.small
                        opacity: 0.7
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacing.small
                visible: root.selectedNote === null

                MaterialIcon {
                    id: emptyIcon

                    Layout.alignment: Qt.AlignHCenter
                    text: "sticky_note_2"
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
                    color: Colours.palette.m3onSurfaceVariant
                    opacity: 0.4

                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: root.selectedNote === null

                        NumberAnimation {
                            to: 1.06
                            duration: Tokens.anim.durations.expressiveSlowEffects
                            easing: Tokens.anim.expressiveSlowEffects
                        }

                        NumberAnimation {
                            to: 1
                            duration: Tokens.anim.durations.expressiveSlowEffects
                            easing: Tokens.anim.expressiveSlowEffects
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Select a note or create one")
                    font: Tokens.font.body.medium
                    opacity: 0.6
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
