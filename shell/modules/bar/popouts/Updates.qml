pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.bar
import qs.modules.nexus

ColumnLayout {
    id: root

    required property PopoutState popouts

    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false

    readonly property int updatesPageIdx: PageRegistry.updatesPageIdx

    readonly property var status: UpdateStatus.describe(null, false)

    readonly property bool checking: UpdateChecker.checkingUpdates

    readonly property string statusText: root.status.title

    readonly property string statusDetail: root.status.detail

    readonly property string statusIcon: root.status.icon

    readonly property string checkActionText: {
        if (root.checking)
            return qsTr("Checking…");
        if (UpdateChecker.checkFailed)
            return qsTr("Try again");
        return qsTr("Check for updates");
    }

    function hideIndicator(): void {
        BarWidgets.setEnabled(GlobalConfig.bar, "updateIndicator", false);
        root.popouts.hasCurrent = false;
    }

    width: Math.max(300 * scaleOffset, _isSidebarOpen ? (Visibilities.sidebarWidthFor(Tokens.sizes.sidebar.width) * scaleOffset) - Tokens.padding.extraLargeIncreased : 0)
    implicitWidth: width
    spacing: Tokens.spacing.small * scaleOffset

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: statusLayout.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
        radius: Tokens.rounding.medium * root.scaleOffset
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        ColumnLayout {
            id: statusLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium * root.scaleOffset
            spacing: Tokens.spacing.small * root.scaleOffset

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small * root.scaleOffset

                MaterialIcon {
                    text: root.statusIcon
                    color: root.status.highlight ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    color: Colours.palette.m3onSurface
                    wrapMode: Text.Wrap
                    font.weight: 600
                    font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.spacing.small * root.scaleOffset + Tokens.font.icon.medium.pointSize * root.fontScale
                visible: text !== ""
                text: root.statusDetail
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.Wrap
                font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: actionsLayout.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
        radius: Tokens.rounding.medium * root.scaleOffset
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        ColumnLayout {
            id: actionsLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium * root.scaleOffset
            spacing: Tokens.spacing.small * root.scaleOffset

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: checkRow.implicitHeight
                radius: Tokens.rounding.full
                color: "transparent"

                StateLayer {
                    anchors.margins: -Tokens.padding.medium / 2 * root.scaleOffset
                    anchors.leftMargin: -Tokens.padding.medium * root.scaleOffset
                    anchors.rightMargin: -Tokens.padding.medium * root.scaleOffset

                    radius: parent.radius
                    enabled: !root.checking
                    onClicked: UpdateChecker.checkNow()
                }

                RowLayout {
                    id: checkRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        text: root.checking ? "progress_activity" : "refresh"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.checkActionText
                        color: Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: openRow.implicitHeight
                radius: Tokens.rounding.full
                color: "transparent"

                StateLayer {
                    anchors.margins: -Tokens.padding.medium / 2 * root.scaleOffset
                    anchors.leftMargin: -Tokens.padding.medium * root.scaleOffset
                    anchors.rightMargin: -Tokens.padding.medium * root.scaleOffset

                    radius: parent.radius
                    onClicked: {
                        root.popouts.hasCurrent = false;
                        WindowFactory.create(null, { initialPageIdx: root.updatesPageIdx });
                    }
                }

                RowLayout {
                    id: openRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        text: "update"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Open Updates")
                        color: Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: hideRow.implicitHeight
                radius: Tokens.rounding.full
                color: "transparent"

                StateLayer {
                    anchors.margins: -Tokens.padding.medium / 2 * root.scaleOffset
                    anchors.leftMargin: -Tokens.padding.medium * root.scaleOffset
                    anchors.rightMargin: -Tokens.padding.medium * root.scaleOffset

                    radius: parent.radius
                    onClicked: root.hideIndicator()
                }

                RowLayout {
                    id: hideRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        text: "visibility_off"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Hide from bar")
                        color: Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }
        }
    }
}
