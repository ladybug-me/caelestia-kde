pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    property string style: Config.osd.style
    readonly property bool isVertical: GlobalConfig.osd.position === "left" || GlobalConfig.osd.position === "right"
    property real sampleValue: 0.72
    property bool sampleMuted: false
    property string sampleType: "volume"

    implicitWidth: 320
    implicitHeight: 140

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        clip: true
        color: Colours.layer(Colours.tPalette.m3surfaceContainerLowest, 1)
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        Loader {
            id: loader

            anchors.centerIn: parent
            width: item ? item.implicitWidth : implicitWidth
            height: item ? item.implicitHeight : implicitHeight
            scale: (root.isVertical && height > 100) ? (100 / height) : 1
            transformOrigin: Item.Center
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
            vertical: root.isVertical
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
            vertical: root.isVertical
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
            vertical: root.isVertical
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
            vertical: root.isVertical
        }
    }

    Component {
        id: defaultComp

        Item {
            implicitWidth: 320
            implicitHeight: 140

            RowLayout {
                anchors.left: parent.left
                anchors.leftMargin: Tokens.padding.extraLarge
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "dock_to_right"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3primary
                }

                StyledText {
                    text: qsTr("Edge Drawer")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }
            }

            StyledRect {
                anchors.right: parent.right
                anchors.rightMargin: GlobalConfig.appearance.islands ? Tokens.padding.small : 0
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 106
                topLeftRadius: Surface.panelRounding
                bottomLeftRadius: Surface.panelRounding
                topRightRadius: GlobalConfig.appearance.islands ? Surface.panelRounding : 0
                bottomRightRadius: GlobalConfig.appearance.islands ? Surface.panelRounding : 0
                color: Colours.layer(Colours.tPalette.m3surfaceContainerHigh, 1)
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                Item {
                    anchors.centerIn: parent
                    width: 28
                    height: 88

                    StyledRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

                        StyledRect {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: parent.height - volHandle.y
                            radius: parent.radius
                            color: Colours.palette.m3secondary
                        }
                    }

                    StyledRect {
                        id: volHandle

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.round((1 - root.sampleValue) * (parent.height - height))
                        width: 28
                        height: 28
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3inverseSurface

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "volume_up"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3inverseOnSurface
                        }
                    }
                }
            }
        }
    }
}

