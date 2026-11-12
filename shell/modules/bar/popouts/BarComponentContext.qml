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
    required property string label
    property string subPage: ""

    // Optional second action row (e.g. every widget menu also links to
    // Elements & Modules). Empty label hides it.
    property string secondLabel: ""
    property string secondSubPage: ""
    property string secondPageKey: "panels"

    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false

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

            ActionRow {
                labelText: root.label
                pageKey: "panels"
                subPage: root.subPage
            }

            ActionRow {
                visible: root.secondLabel !== ""
                labelText: root.secondLabel
                pageKey: root.secondPageKey
                subPage: root.secondSubPage
            }
        }
    }

    component ActionRow: StyledRect {
        id: row

        required property string labelText
        required property string pageKey
        property string subPage: ""

        Layout.fillWidth: true
        implicitWidth: rowLayout.implicitWidth + Tokens.padding.medium * 2 * root.scaleOffset
        implicitHeight: rowLayout.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset

        radius: Tokens.rounding.medium * root.scaleOffset
        color: "transparent"

        StateLayer {
            anchors.fill: parent
            radius: row.radius

            onClicked: {
                root.popouts.hasCurrent = false;
                WindowFactory.create(null, {
                    initialPageIdx: PageRegistry.indexForKey(row.pageKey),
                    initialSubPage: row.subPage
                });
            }
        }

        RowLayout {
            id: rowLayout

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
                text: row.labelText
                color: Colours.palette.m3onSurface
                font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
            }
        }
    }
}
