pragma ComponentBehavior: Bound

import ".."
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Caelestia.Config
import qs.components
import qs.components.controls as Controls
import qs.components.filedialog
import qs.services
import qs.utils

// A live view of a real folder, like Plasma's Folder View: scroll through it,
// open files, drag them out, and drop files on it to move them in.
Item {
    id: root

    property var frame
    property var controller

    readonly property string path: frame?.config.path ?? ""
    readonly property string folderName: path.substring(path.lastIndexOf("/") + 1) || path
    readonly property real slotWidth: Math.max(controller.iconSize * 0.6, 40) + Tokens.padding.medium * 2
    readonly property real slotHeight: controller.iconSize * 0.6 + Tokens.padding.small * 2 + 30
    property string selectedPath: ""

    function chooseFolder(): void {
        dialog.open();
    }

    function openInFileManager(): void {
        Launch.exec(["xdg-open", path]);
    }

    function open(entry: var): void {
        entry.launch();
        selectedPath = "";
    }

    FileDialog {
        id: dialog

        selectFolder: true
        title: qsTr("Choose a folder to show")
        cwd: root.path.startsWith(Paths.home) ? ["Home", ...root.path.substring(Paths.home.length).split("/").filter(s => s.length > 0)] : ["Home"]
        onAccepted: path => root.frame.setConfig({ path: path.replace(/^file:\/\//, "").replace(/\/+$/, "") })
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "folder_open"
                color: Colours.palette.m3primary
            }

            StyledText {
                Layout.fillWidth: true
                text: root.folderName
                font: Tokens.font.title.small
                elide: Text.ElideMiddle
            }

            Controls.IconButton {
                type: Controls.IconButton.Text
                icon: "drive_folder_upload"
                onClicked: root.chooseFolder()
            }

            Controls.IconButton {
                type: Controls.IconButton.Text
                icon: "open_in_new"
                onClicked: root.openInFileManager()
            }
        }

        GridView {
            id: view

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            // Scrolled with the wheel only, so that dragging moves files.
            interactive: false
            cellWidth: width / Math.max(1, Math.floor(width / root.slotWidth))
            cellHeight: root.slotHeight
            boundsBehavior: Flickable.StopAtBounds

            model: FolderListModel {
                folder: root.path !== "" ? "file://" + root.path : ""
                showDirsFirst: true
                showHidden: false
                sortCaseSensitive: false
            }

            ScrollBar.vertical: Controls.StyledScrollBar {
                flickable: view
            }

            delegate: Item {
                id: item

                required property string fileName
                required property string filePath
                required property bool fileIsDir
                required property string fileSuffix
                required property var fileModified
                required property var fileSize

                width: view.cellWidth
                height: view.cellHeight

                FileEntry {
                    id: entry

                    fileName: item.fileName
                    filePath: item.filePath
                    fileIsDir: item.fileIsDir
                    fileSuffix: item.fileSuffix
                    fileModified: item.fileModified
                    fileSize: item.fileSize
                }

                StyledRect {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Tokens.rounding.medium
                    color: root.selectedPath === entry.path ? Qt.alpha(Colours.palette.m3primary, 0.24) : Qt.alpha(Colours.palette.m3onSurface, itemArea.containsMouse ? 0.1 : 0)
                }

                Column {
                    id: visual

                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.small * 2
                    spacing: Tokens.spacing.extraSmall

                    EntryIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.controller.iconSize * 0.6
                        height: width
                        entry: entry
                        materialYou: root.controller.materialYou
                        vibrant: root.controller.vibrant
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: entry.displayName
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font: Tokens.font.label.small
                    }
                }

                MouseArea {
                    id: itemArea

                    property point pressPos
                    property bool dragSent: false

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: DesktopLayout.singleClick ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: mouse => {
                        pressPos = Qt.point(mouse.x, mouse.y);
                        dragSent = false;
                        root.controller.grabKeyboard();
                        root.selectedPath = entry.path;
                    }
                    onPositionChanged: mouse => {
                        if (!(pressedButtons & Qt.LeftButton) || dragSent)
                            return;
                        const dx = mouse.x - pressPos.x;
                        const dy = mouse.y - pressPos.y;
                        if (dx * dx + dy * dy >= Qt.styleHints.startDragDistance * Qt.styleHints.startDragDistance) {
                            dragSent = true;
                            root.controller.beginFileDrag([entry.url], visual, pressPos.x - visual.x, pressPos.y - visual.y);
                        }
                    }
                    onClicked: mouse => {
                        if (dragSent)
                            return;
                        if (mouse.button === Qt.RightButton) {
                            const p = mapToItem(root.controller, mouse.x, mouse.y);
                            fileMenu.openAt(p.x, p.y, entry);
                        } else if (DesktopLayout.singleClick) {
                            root.open(entry);
                        }
                    }
                    onDoubleClicked: mouse => {
                        if (mouse.button === Qt.LeftButton && !DesktopLayout.singleClick)
                            root.open(entry);
                    }
                }
            }

            WheelHandler {
                acceptedModifiers: Qt.NoModifier
                onWheel: event => view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY - event.angleDelta.y))
            }

            StyledText {
                anchors.centerIn: parent
                visible: view.count === 0
                text: qsTr("Empty folder")
                color: Colours.palette.m3outline
            }
        }
    }

    Controls.Menu {
        id: fileMenu

        property var entry: null

        function openAt(x: real, y: real, target: var): void {
            entry = target;
            anchor.x = x;
            anchor.y = y;
            const bgW = backgroundItem && backgroundItem.implicitWidth > 0 ? backgroundItem.implicitWidth : 240;
            const bgH = backgroundItem && backgroundItem.implicitHeight > 0 ? backgroundItem.implicitHeight : 220;
            marginX = x + bgW > root.controller.width ? -bgW : 0;
            marginY = y + bgH > root.controller.height ? -bgH : 0;
            expanded = true;
        }

        attachTo: anchor
        z: 9999
        attachSideX: Controls.Menu.Left
        attachSideY: Controls.Menu.Top
        thisSideX: Controls.Menu.Left
        thisSideY: Controls.Menu.Top

        items: [
            Controls.MenuItem {
                text: qsTr("Open")
                icon: "open_in_new"
                onClicked: root.open(fileMenu.entry)
            },
            Controls.MenuItem {
                text: qsTr("Copy")
                icon: "content_copy"
                onClicked: root.controller.copyUrls([fileMenu.entry.url], false)
            },
            Controls.MenuItem {
                text: qsTr("Cut")
                icon: "content_cut"
                onClicked: root.controller.copyUrls([fileMenu.entry.url], true)
            },
            Controls.MenuItem {
                text: qsTr("Move to Trash")
                icon: "delete"
                onClicked: root.controller.runFileOp(["kioclient", "move", fileMenu.entry.url, "trash:/"], qsTr("File operation failed"), null)
            }
        ]

        Item {
            id: anchor

            parent: root.controller
        }
    }
}
