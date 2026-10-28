pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus

ColumnLayout {
    id: root

    required property PopoutState popouts

    property real scaleOffset: 1.0
    property real fontScale: 1.0

    readonly property bool isPanel: root.popouts.panelIndex >= 0
    readonly property var allEdges: ["top", "bottom", "left", "right"]
    readonly property var freeEdges: BarPanels.freeEdges("")

    function edgeName(edge: string): string {
        switch (edge) {
        case "top":
            return qsTr("top");
        case "bottom":
            return qsTr("bottom");
        case "left":
            return qsTr("left");
        default:
            return qsTr("right");
        }
    }
    function addBar(position: string): void {
        root.popouts.hasCurrent = false;
        BarPanels.addPanel(position);
    }
    function openBarSettings(): void {
        const target = root.popouts.panelIndex;
        root.popouts.hasCurrent = false;
        WindowFactory.openBarSettings(target);
    }
    function removeThisPanel(): void {
        root.popouts.hasCurrent = false;
        BarPanels.removePanel(root.popouts.panelIndex);
    }


    width: card.implicitWidth
    implicitWidth: card.implicitWidth
    spacing: Tokens.spacing.medium * scaleOffset

    StyledRect {
        id: card

        Layout.fillWidth: true
        implicitWidth: cardLayout.implicitWidth + Tokens.padding.medium * 2 * root.scaleOffset
        implicitHeight: cardLayout.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
        radius: Tokens.rounding.medium * root.scaleOffset
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        ColumnLayout {
            id: cardLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium * root.scaleOffset
            spacing: Tokens.spacing.small * root.scaleOffset

            StyledRect {
                id: editRow

                Layout.fillWidth: true
                implicitWidth: editLayout.implicitWidth + Tokens.padding.medium * 2 * root.scaleOffset
                implicitHeight: editLayout.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset
                radius: Tokens.rounding.medium * root.scaleOffset
                color: "transparent"

                StateLayer {
                    anchors.fill: parent
                    radius: editRow.radius

                    onClicked: {
                        const target = root.popouts.panelIndex;
                        root.popouts.hasCurrent = false;
                        WindowFactory.openBarComponents(target);
                    }
                }

                RowLayout {
                    id: editLayout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.medium * root.scaleOffset
                    anchors.rightMargin: Tokens.padding.medium * root.scaleOffset
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        text: "tune"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.isPanel ? qsTr("Edit this panel") : qsTr("Edit this bar")
                        color: Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }
            Repeater {
                model: root.freeEdges

            StyledRect {
                id: addRow

                required property string modelData

                Layout.fillWidth: true
                implicitHeight: addRowLayout.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset
                radius: Tokens.rounding.medium * root.scaleOffset
                color: "transparent"

                StateLayer {
                    anchors.fill: parent
                    radius: addRow.radius

                    onClicked: root.addBar(modelData)
                }

                RowLayout {
                    id: addRowLayout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.medium * root.scaleOffset
                    anchors.rightMargin: Tokens.padding.medium * root.scaleOffset
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        text: "add"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: qsTr("Add bar on the %1").arg(root.edgeName(modelData))
                        color: Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }
            }

            StyledRect {
                id: settingsRow

                Layout.fillWidth: true
                implicitHeight: settingsRowLayout.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset
                radius: Tokens.rounding.medium * root.scaleOffset
                color: "transparent"

                StateLayer {
                    anchors.fill: parent
                    radius: settingsRow.radius

                    onClicked: root.openBarSettings()
                }

                RowLayout {
                    id: settingsRowLayout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.medium * root.scaleOffset
                    anchors.rightMargin: Tokens.padding.medium * root.scaleOffset
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        text: "settings"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.isPanel ? qsTr("Settings of this panel") : qsTr("Settings of this bar")
                        color: Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }

            StyledRect {
                id: removeRow

                visible: root.isPanel

                Layout.fillWidth: true
                implicitHeight: removeRowLayout.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset
                radius: Tokens.rounding.medium * root.scaleOffset
                color: "transparent"

                StateLayer {
                    anchors.fill: parent
                    radius: removeRow.radius

                    onClicked: root.removeThisPanel()
                }

                RowLayout {
                    id: removeRowLayout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.medium * root.scaleOffset
                    anchors.rightMargin: Tokens.padding.medium * root.scaleOffset
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        text: "delete"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: qsTr("Remove this panel")
                        color: Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }
        }
    }
}
