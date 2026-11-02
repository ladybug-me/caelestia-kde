pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services as QsServices

ColumnLayout {
    id: root

    required property PopoutState popouts

    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false

    width: Math.max(300 * scaleOffset, _isSidebarOpen ? (QsServices.Visibilities.sidebarWidthFor(Tokens.sizes.sidebar.width) * scaleOffset) - Tokens.padding.extraLargeIncreased : 0)
    implicitWidth: width
    spacing: Tokens.spacing.small * root.scaleOffset

    StyledText {
        Layout.topMargin: Tokens.padding.medium * root.scaleOffset
        Layout.leftMargin: Tokens.padding.small * root.scaleOffset
        text: qsTr("Privacy")
        font.weight: 500
        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
    }

    Repeater {
        model: ScriptModel {
            values: [
                { icon: "mic", label: qsTr("Microphone"), apps: QsServices.Privacy.microphoneApps },
                { icon: "videocam", label: qsTr("Video capture"), apps: QsServices.Privacy.videoApps }
            ].filter(row => row.apps.length > 0)
        }

        delegate: StyledRect {
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: entryLayout.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
            radius: Tokens.rounding.medium * root.scaleOffset
            color: QsServices.Colours.tPalette.m3surfaceContainer
            clip: true

            ColumnLayout {
                id: entryLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.medium * root.scaleOffset
                spacing: Tokens.spacing.small * root.scaleOffset

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small * root.scaleOffset

                    MaterialIcon {
                        id: entryIcon

                        text: modelData.icon
                        color: QsServices.Colours.palette.m3primary
                        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: QsServices.Colours.palette.m3onSurface
                        elide: Text.ElideRight
                        font.weight: 600
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }

                Repeater {
                    model: modelData.apps

                    StyledText {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.leftMargin: entryIcon.implicitWidth + Tokens.spacing.small * root.scaleOffset
                        text: modelData
                        color: QsServices.Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                        font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
                    }
                }
            }
        }
    }

    StyledText {
        visible: !QsServices.Privacy.inUse
        Layout.fillWidth: true
        Layout.margins: Tokens.padding.medium * root.scaleOffset
        text: qsTr("Nothing is using the microphone or capturing the screen.")
        color: QsServices.Colours.palette.m3onSurfaceVariant
        wrapMode: Text.Wrap
        font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
    }
}
