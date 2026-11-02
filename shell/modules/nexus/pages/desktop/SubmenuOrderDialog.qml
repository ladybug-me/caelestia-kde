pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.nexus.common

Popup {
    id: root

    property var entry: null
    property var target: null

    readonly property real rowsHeight: rowsModel.count > 0 ? rowsModel.count * 44 + (rowsModel.count - 1) * Tokens.spacing.extraSmall : 0

    signal saved(var children)

    function openIn(win, target): void {
        if (win && win.contentItem)
            parent = win.contentItem;
        root.target = target || null;
        open();
    }

    width: 340
    padding: 24
    height: contentColumn.implicitHeight + 48
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    x: {
        if (!parent)
            return 0;
        if (!root.target)
            return Math.round((parent.width - width) / 2);
        const centred = root.target.mapToItem(parent, 0, 0).x + (root.target.width - width) / 2;
        return Math.round(Math.max(8, Math.min(parent.width - width - 8, centred)));
    }
    y: parent ? Math.round((parent.height - height) / 2) : 0

    enter: DialogTransition { }
    exit: DialogTransition {
        exiting: true
    }

    onOpened: {
        rowsModel.clear();
        const children = root.entry && root.entry.children ? root.entry.children : [];
        for (const child of children)
            rowsModel.append({
                label: child.label || "",
                icon: child.icon || "widgets",
                raw: JSON.stringify(child)
            });
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

    contentItem: ColumnLayout {
        id: contentColumn

        spacing: Tokens.spacing.small

        Text {
            text: qsTr("Order the submenu")
            font: Tokens.font.body.large
            color: Colours.palette.m3onSurface
            Layout.fillWidth: true
        }

        Text {
            text: qsTr("Drag the rows to change the order they unfold in.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.padding.small
        }

        ListView {
            id: list

            Layout.fillWidth: true
            Layout.preferredHeight: root.rowsHeight
            implicitHeight: root.rowsHeight
            interactive: false
            spacing: Tokens.spacing.extraSmall
            model: ListModel {
                id: rowsModel
            }

            delegate: Item {
                id: dragWrapper

                required property int index
                required property string label
                required property string icon

                readonly property bool isDragging: dragArea.drag.active

                width: list.width
                height: 44
                z: isDragging ? 100 : 1

                DropArea {
                    anchors.fill: parent
                    keys: ["subrow"]
                    onEntered: drag => {
                        const source = drag.source;
                        if (!source || source.index === dragWrapper.index)
                            return;
                        rowsModel.move(source.index, dragWrapper.index, 1);
                    }
                }

                StyledRect {
                    id: rowRect

                    width: dragWrapper.width
                    height: dragWrapper.height
                    radius: Tokens.rounding.medium
                    color: dragWrapper.isDragging ? Colours.layer(Colours.palette.m3surfaceContainerHighest, 2) : Colours.palette.m3surfaceContainer

                    Drag.active: dragArea.drag.active
                    Drag.source: dragWrapper
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    Drag.keys: ["subrow"]

                    states: State {
                        when: dragArea.drag.active

                        ParentChange { target: rowRect; parent: list.contentItem }
                        PropertyChanges { target: rowRect; scale: NexusStyle.dragScale }
                    }

                    MouseArea {
                        id: dragArea

                        anchors.fill: parent
                        hoverEnabled: true
                        drag.target: rowRect
                        drag.axis: Drag.YAxis

                        onReleased: {
                            rowRect.x = 0;
                            rowRect.y = 0;
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.medium
                        acceptedButtons: Qt.NoButton
                        color: Colours.palette.m3onSurface
                        opacity: dragArea.containsMouse && !dragWrapper.isDragging ? 0.08 : 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.FastEffects
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: dragWrapper.icon
                            color: Colours.palette.m3onSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            text: dragWrapper.label
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurface
                            elide: Text.ElideRight
                        }

                        MaterialIcon {
                            text: "drag_indicator"
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.padding.small

            TextButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            Item { Layout.fillWidth: true }

            TextButton {
                text: qsTr("Save")
                onClicked: {
                    const children = [];
                    for (let i = 0; i < rowsModel.count; i++)
                        children.push(JSON.parse(rowsModel.get(i).raw));
                    root.saved(children);
                    root.close();
                }
            }
        }
    }
}
