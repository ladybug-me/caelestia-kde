pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus

ColumnLayout {
    id: root

    required property PopoutState popouts

    // Injected by Content.qml's Popout.
    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false

    width: 200 * scaleOffset
    implicitWidth: 200 * scaleOffset
    spacing: Tokens.spacing.medium * scaleOffset

    StyledRect {
        Layout.fillWidth: true
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

            // Clock Settings action
            StyledRect {
                id: settingsItem

                Layout.fillWidth: true
                implicitHeight: settingsRow.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset

                radius: Tokens.rounding.medium * root.scaleOffset
                color: "transparent"

                StateLayer {
                    anchors.fill: parent
                    radius: settingsItem.radius

                    onClicked: {
                        root.popouts.hasCurrent = false;
                        WindowFactory.create(null, {
                            initialPageIdx: PageRegistry.indexForKey("panels"),
                            initialSubPageIdx: 11
                        });
                    }
                }

                RowLayout {
                    id: settingsRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        text: "settings"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: qsTr("Clock settings")
                        color: Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }
        }
    }
}
