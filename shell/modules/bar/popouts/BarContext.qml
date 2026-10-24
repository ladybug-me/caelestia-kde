pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.nexus

ColumnLayout {
    id: root

    required property PopoutState popouts

    property real scaleOffset: 1.0
    property real fontScale: 1.0

    readonly property bool isPanel: root.popouts.panelIndex >= 0

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
        }
    }
}
