pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property string style: Config.osd.style
    property real sampleValue: 0.72
    property bool sampleMuted: false
    property string sampleType: "volume"

    implicitWidth: 320
    implicitHeight: 140

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.layer(Colours.tPalette.m3surfaceContainerLowest, 1)
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        Loader {
            id: loader

            anchors.centerIn: parent
            sourceComponent: {
                switch (root.style) {
                    case "pill": return pillComp;
                    case "compact": return compactComp;
                    case "radial": return radialComp;
                    case "card": return cardComp;
                    case "bar": return barComp;
                    default: return defaultComp;
                }
            }
        }
    }

    Component {
        id: pillComp

        PillOsd {
            value: root.sampleValue
            isMuted: root.sampleMuted
            icon: "volume_up"
            title: qsTr("Volume")
            type: root.sampleType
        }
    }

    Component {
        id: compactComp

        CompactOsd {
            value: root.sampleValue
            isMuted: root.sampleMuted
            icon: "volume_up"
            title: qsTr("Volume")
            type: root.sampleType
        }
    }

    Component {
        id: radialComp

        RadialOsd {
            value: root.sampleValue
            isMuted: root.sampleMuted
            icon: "volume_up"
            title: qsTr("Volume")
            type: root.sampleType
        }
    }

    Component {
        id: cardComp

        CardOsd {
            value: root.sampleValue
            isMuted: root.sampleMuted
            icon: "volume_up"
            title: qsTr("Volume")
            type: root.sampleType
        }
    }

    Component {
        id: barComp

        MinimalBarOsd {
            value: root.sampleValue
            isMuted: root.sampleMuted
            icon: "volume_up"
            title: qsTr("Volume")
            type: root.sampleType
        }
    }

    Component {
        id: defaultComp

        Item {
            implicitWidth: 260
            implicitHeight: 90

            RowLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacing.large

                StyledRect {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 70
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.tPalette.m3surfaceContainerHigh, 1)
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.extraSmall
                        spacing: 4

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: "volume_up"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledRect {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillHeight: true
                            Layout.preferredWidth: 6
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3surfaceContainerHighest

                            StyledRect {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * 0.72
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3primary
                            }
                        }
                    }
                }

                ColumnLayout {
                    spacing: 4

                    StyledText {
                        text: qsTr("Edge Drawer")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        text: qsTr("Slides out from the right screen edge")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3outline
                    }
                }
            }
        }
    }
}

