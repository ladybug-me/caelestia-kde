pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog as FileDialogComp
import qs.components.images
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property var popouts

    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false

    property var notes: []
    property int selectedIndex: -1
    readonly property var selectedNote: root.selectedIndex >= 0 && root.selectedIndex < root.notes.length ? root.notes[root.selectedIndex] : null

    // Managed media library: uploads are copied under notes/audio|images
    // so notes survive the original files being moved or deleted.
    readonly property string notesMediaDir: Paths.state + "/notes"

    function newNote(type: string): void {
        const note = {
            id: Date.now(),
            type: type,
            title: qsTr("Untitled"),
            body: "",
            items: [],
            audioPath: "",
            imagePath: "",
            caption: "",
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

    function updateSelected(field: string, value: var): void {
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

    function importFile(field: string, src: string, subdir: string): void {
        if (!root.selectedNote || !src)
            return;
        let clean = src;
        if (clean.startsWith("file://"))
            clean = clean.substring(7);
        const base = clean.split("/").pop();
        if (!base)
            return;
        fileCopier.srcPath = clean;
        fileCopier.destPath = root.notesMediaDir + "/" + subdir + "/" + root.selectedNote.id + "-" + base;
        fileCopier.destField = field;
        fileCopier.running = true;
    }

    width: 560
    spacing: Tokens.spacing.small
    Component.onCompleted: {
        fileView.reload();
        dirMaker.running = true;
    }


    Process {
        id: dirMaker

        command: ["mkdir", "-p", root.notesMediaDir + "/audio", root.notesMediaDir + "/images"]
    }

    Process {
        id: fileCopier

        property string srcPath: ""
        property string destPath: ""
        property string destField: ""

        command: ["cp", srcPath, destPath]
        onExited: code => {
            if (code === 0 && destField !== "")
                root.updateSelected(destField, destPath);
            srcPath = "";
            destPath = "";
            destField = "";
        }
    }


    FileView {
        id: fileView

        path: `${Paths.state}/notes_tab.json`
        watchChanges: false
        printErrors: false

        onLoaded: {
            console.log("NOTES loaded: " + fileView.text());
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

    // Header with note type buttons
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: qsTr("Notes")
            font: Tokens.font.body.builders.large.size(20).weight(Font.DemiBold).build()
            color: Colours.palette.m3onSurface
            Layout.fillWidth: true
        }

        IconButton {
            icon: "subject"
            onClicked: root.newNote("text")
        }

        IconButton {
            icon: "checklist"
            onClicked: root.newNote("list")
        }

        IconButton {
            icon: "mic"
            onClicked: root.newNote("audio")
        }

        IconButton {
            icon: "image"
            onClicked: root.newNote("image")
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    // List + editor side by side
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

    // Notes list
    Flickable {
        Layout.preferredWidth: 220
        Layout.preferredHeight: 350
        contentWidth: width
        contentHeight: listCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: listCol

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

                    Behavior on color {
                        CAnim {}
                    }

                    Behavior on radius {
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

                            MaterialIcon {
                                text: {
                                    const t = noteItem.modelData.type || "text";
                                    if (t === "list")
                                        return "checklist";
                                    if (t === "audio")
                                        return "mic";
                                    if (t === "image")
                                        return "image";
                                    return "subject";
                                }
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3onSurfaceVariant
                                opacity: 0.7
                            }

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
                            visible: {
                                const t = noteItem.modelData.type;
                                return !t || t === "text";
                            }
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

    StyledRect {
        Layout.fillHeight: true
        Layout.preferredHeight: 350
        implicitWidth: 1
        color: Colours.palette.m3outlineVariant
    }

    // Editor
    ColumnLayout {
        id: editorCol

        property var trackedId: root.selectedNote ? root.selectedNote.id : null

        Layout.fillWidth: true
        // Top-aligned so the rest position (y=0) matches the switch animation
        Layout.alignment: Qt.AlignTop
        spacing: Tokens.spacing.medium
        visible: root.selectedNote !== null

        onTrackedIdChanged: {
            switchAnim.restart();
        }

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
            Layout.preferredHeight: 200
            Layout.fillHeight: true
            visible: root.selectedNote && (root.selectedNote.type === "text" || !root.selectedNote.type)
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

        // List editor
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            visible: root.selectedNote && root.selectedNote.type === "list"

            Repeater {
                model: root.selectedNote && root.selectedNote.items ? root.selectedNote.items : []

                delegate: RowLayout {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledRect {
                        id: checkBox

                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 24
                        implicitHeight: 24

                        radius: Tokens.rounding.medium
                        color: "transparent"
                        border.width: 2
                        border.color: modelData.checked ?? false ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "check"
                            fontStyle: Tokens.font.icon.builders.small.weight(Font.DemiBold).build()
                            color: Colours.palette.m3primary
                            scale: modelData.checked ? 1 : 0
                        }

                        CustomMouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const arr = (root.selectedNote.items || []).slice();
                                arr[index] = Object.assign({}, arr[index], { checked: !modelData.checked });
                                root.updateSelected("items", arr);
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: itemInput.implicitHeight
                        Layout.alignment: Qt.AlignVCenter
                        opacity: (modelData.checked ?? false) ? 0.6 : 1

                        TextInput {
                            id: itemInput

                            function commitItem(): void {
                                if (text !== (modelData.text ?? "")) {
                                    const arr = (root.selectedNote.items || []).slice();
                                    arr[index] = Object.assign({}, arr[index], { text: text });
                                    root.updateSelected("items", arr);
                                }
                            }

                            anchors.fill: parent
                            text: modelData.text ?? ""
                            font: Tokens.font.body.medium
                            color: (modelData.checked ?? false) ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                            selectByMouse: true
                            selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                            selectedTextColor: color
                            renderType: TextInput.NativeRendering

                            onAccepted: commitItem()
                            onEditingFinished: commitItem()
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: itemInput.text.length === 0
                            text: qsTr("List item")
                            font: itemInput.font
                            opacity: 0.5
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(itemInput.contentWidth, parent.width)
                            height: 1
                            visible: modelData.checked ?? false
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }

            TextButton {
                text: qsTr("Add item")
                type: TextButton.Tonal
                onClicked: {
                    const arr = ((root.selectedNote && root.selectedNote.items) || []).slice();
                    arr.push({ text: "", checked: false });
                    root.updateSelected("items", arr);
                }
            }
        }

        // Audio editor
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: root.selectedNote && root.selectedNote.type === "audio"

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                TextButton {
                    text: audioPlayer.playing ? qsTr("Pause") : qsTr("Play")
                    type: TextButton.Tonal
                    enabled: root.selectedNote && root.selectedNote.audioPath !== ""
                    onClicked: audioPlayer.playing ? audioPlayer.pause() : audioPlayer.play()
                }

                TextButton {
                    text: voiceRecorder.recorderState === MediaRecorder.RecordingState ? qsTr("Stop") : qsTr("Record")
                    type: TextButton.Tonal
                    onClicked: {
                        if (voiceRecorder.recorderState === MediaRecorder.RecordingState) {
                            voiceRecorder.stop();
                        } else if (root.selectedNote) {
                            voiceRecorder.outputLocation = Qt.resolvedUrl(root.notesMediaDir + "/audio/note-" + root.selectedNote.id + ".m4a");
                            voiceRecorder.record();
                        }
                    }
                }

                TextButton {
                    text: qsTr("Upload")
                    type: TextButton.Tonal
                    onClicked: audioPicker.open()
                }
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: root.selectedNote && root.selectedNote.audioPath ? root.selectedNote.audioPath.split("/").pop() : qsTr("No audio yet")
                font: Tokens.font.body.small
                opacity: 0.7
                color: Colours.palette.m3onSurfaceVariant
            }

            MediaPlayer {
                id: audioPlayer

                source: root.selectedNote && root.selectedNote.audioPath ? Qt.resolvedUrl(root.selectedNote.audioPath) : ""
                audioOutput: AudioOutput {}
            }

            CaptureSession {
                id: captureSession

                audioInput: AudioInput {}
                recorder: MediaRecorder {
                    id: voiceRecorder

                    onRecorderStateChanged: {
                        if (voiceRecorder.recorderState === MediaRecorder.StoppedState) {
                            const loc = voiceRecorder.actualLocation.toString();
                            if (loc !== "" && (!root.selectedNote || root.selectedNote.audioPath !== loc))
                                root.updateSelected("audioPath", loc);
                        }
                    }
                }
            }
        }

        // Image editor
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: root.selectedNote && root.selectedNote.type === "image"

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                TextButton {
                    text: qsTr("Upload")
                    type: TextButton.Tonal
                    onClicked: imagePicker.open()
                }

                StyledTextField {
                    id: urlField

                    Layout.fillWidth: true
                    placeholderText: qsTr("Paste image URL…")
                    onAccepted: {
                        root.updateSelected("imagePath", text);
                        urlField.clear();
                    }
                }
            }

            FadeImage {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                visible: root.selectedNote && root.selectedNote.imagePath !== ""
                source: root.selectedNote ? root.selectedNote.imagePath : ""
                fillMode: Image.PreserveAspectCrop
            }

            StyledText {
                Layout.fillWidth: true
                visible: !(root.selectedNote && root.selectedNote.imagePath !== "")
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("No image yet")
                font: Tokens.font.body.small
                opacity: 0.6
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledTextField {
                Layout.fillWidth: true
                text: root.selectedNote && root.selectedNote.caption ? root.selectedNote.caption : ""
                placeholderText: qsTr("Add a caption…")
                font: Tokens.font.body.small
                onEditingFinished: root.updateSelected("caption", text)
            }
        }

        FileDialogComp.FileDialog {
            id: audioPicker

            title: qsTr("Select audio file")
            filterLabel: qsTr("Audio files")
            filters: ["mp3", "ogg", "wav", "flac", "m4a"]
            onAccepted: path => root.importFile("audioPath", path, "audio")
        }

        FileDialogComp.FileDialog {
            id: imagePicker

            title: qsTr("Select image")
            filterLabel: qsTr("Image files")
            filters: Images.validImageExtensions
            onAccepted: path => root.importFile("imagePath", path, "images")
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

    // Empty editor placeholder (no note selected)
    ColumnLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 350
        spacing: Tokens.spacing.small
        visible: root.selectedNote === null

        Item { Layout.fillHeight: true }

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: "sticky_note_2"
            fontStyle: Tokens.font.icon.extraLarge
            color: Colours.palette.m3onSurfaceVariant
            opacity: 0.4
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Select a note")
            font: Tokens.font.body.medium
            opacity: 0.6
            color: Colours.palette.m3onSurfaceVariant
        }

        Item { Layout.fillHeight: true }
    }
    }
}
