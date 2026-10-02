pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// A desktop icon: a file, a launcher or a group of them. Only draws and
// reports pointer input; the owner decides what selection and clicks mean.
Item {
    id: root

    property string key
    property var entry: null
    property var groupMembers: []
    property string groupName
    property bool isGroup: false

    property int iconSize: 64
    property bool materialYou: false
    property bool vibrant: false
    property bool pointingCursor: false

    property bool selected: false
    property bool focusVisible: false
    property bool dimmed: false
    property bool mergeTarget: false
    property bool renaming: false
    property real appear: 0

    readonly property string label: isGroup ? groupName : (entry?.displayName ?? "")
    readonly property alias iconItem: iconBox
    readonly property bool hovered: mouseArea.containsMouse

    signal pressed(var mouse)
    signal clicked(var mouse)
    signal doubleClicked(var mouse)
    signal contextMenuRequested(real x, real y)
    signal dragRequested(real x, real y)
    signal renameCommitted(string text)
    signal renameCancelled

    function startRename(text: string, selectUntil: int): void {
        renaming = true;
        renameField.text = text;
        if (selectUntil > 0)
            renameField.select(0, selectUntil);
        else
            renameField.selectAll();
        renameField.forceActiveFocus();
    }

    function commitRename(): void {
        if (!renaming)
            return;
        renaming = false;
        renameCommitted(renameField.text);
    }

    function cancelRename(): void {
        if (!renaming)
            return;
        renaming = false;
        renameCancelled();
    }

    // Is the point (in tile coordinates) over the icon itself rather than its
    // label or padding? Dropping there merges instead of placing.
    function overIcon(x: real, y: real): bool {
        const p = iconBox.mapFromItem(root, x, y);
        return p.x >= 0 && p.y >= 0 && p.x <= iconBox.width && p.y <= iconBox.height;
    }

    opacity: (dimmed ? 0.4 : 1) * appear
    scale: 0.85 + 0.15 * appear
    Component.onCompleted: appear = 1

    Behavior on appear {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.FastEffects
        }
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.medium
        color: root.selected ? Qt.alpha(Colours.palette.m3primary, root.hovered ? 0.32 : 0.24) : Qt.alpha(Colours.palette.m3onSurface, root.hovered ? 0.1 : 0)
        border.width: root.focusVisible ? 2 : 0
        border.color: Colours.palette.m3primary
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        spacing: Tokens.spacing.small

        // Fixed height so the icon stays put whether the label wraps to one or two lines.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.iconSize

            Item {
                id: iconBox

                anchors.centerIn: parent
                width: root.iconSize
                height: root.iconSize
                scale: root.mergeTarget ? 1.12 : 1

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                // Backdrop that forms a group when another icon hovers over this one.
                StyledRect {
                    anchors.centerIn: parent
                    width: parent.width * 1.15
                    height: parent.height * 1.15
                    radius: Tokens.rounding.large
                    color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.85)
                    border.width: root.mergeTarget ? 2 : 0
                    border.color: Colours.palette.m3primary
                    opacity: root.isGroup || root.mergeTarget ? 1 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }
                }

                EntryIcon {
                    anchors.fill: parent
                    visible: !root.isGroup
                    entry: root.entry
                    materialYou: root.materialYou
                    vibrant: root.vibrant
                }

                Grid {
                    anchors.centerIn: parent
                    visible: root.isGroup
                    columns: 2
                    spacing: root.iconSize * 0.08

                    Repeater {
                        model: root.isGroup ? root.groupMembers.slice(0, 4) : []

                        EntryIcon {
                            required property var modelData

                            width: root.iconSize * 0.4
                            height: root.iconSize * 0.4
                            entry: modelData
                            materialYou: root.materialYou
                            vibrant: root.vibrant
                        }
                    }
                }
            }
        }

        Text {
            visible: !root.renaming
            Layout.fillWidth: true
            Layout.fillHeight: true
            verticalAlignment: Text.AlignTop
            text: root.label
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.small
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            style: Text.Outline
            styleColor: Colours.palette.m3surface
        }

        StyledTextField {
            id: renameField

            visible: root.renaming
            Layout.fillWidth: true
            // No outline: the editor takes the label's place and should look like it.
            background.visible: false
            onAccepted: root.commitRename()
            onActiveFocusChanged: {
                // Clicking anywhere outside the editor applies the rename.
                if (!activeFocus && root.renaming)
                    root.commitRename();
            }
            Keys.onEscapePressed: root.cancelRename()

            // The window only gets keyboard focus once the compositor applies the
            // exclusive grab, after startRename() has run; focus the editor then.
            Connections {
                function onActiveChanged(): void {
                    if (renameField.Window.window.active)
                        renameField.forceActiveFocus();
                }

                target: renameField.Window.window
                enabled: root.renaming
            }
        }

        Item {
            visible: root.renaming
            Layout.fillHeight: true
        }
    }

    MouseArea {
        id: mouseArea

        property point pressPos
        property bool dragSent: false

        anchors.fill: parent
        enabled: !root.renaming
        hoverEnabled: true
        cursorShape: root.pointingCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            pressPos = Qt.point(mouse.x, mouse.y);
            dragSent = false;
            root.pressed(mouse);
        }
        onPositionChanged: mouse => {
            if (!(pressedButtons & Qt.LeftButton) || dragSent)
                return;
            const dx = mouse.x - pressPos.x;
            const dy = mouse.y - pressPos.y;
            if (dx * dx + dy * dy >= Qt.styleHints.startDragDistance * Qt.styleHints.startDragDistance) {
                dragSent = true;
                root.dragRequested(pressPos.x, pressPos.y);
            }
        }
        onClicked: mouse => {
            if (dragSent)
                return;
            if (mouse.button === Qt.RightButton)
                root.contextMenuRequested(mouse.x, mouse.y);
            else
                root.clicked(mouse);
        }
        onDoubleClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.doubleClicked(mouse);
        }
    }
}
