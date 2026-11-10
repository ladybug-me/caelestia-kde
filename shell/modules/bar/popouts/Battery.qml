pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property PopoutState popouts
    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false

    // PowerProfiles.degradationReason is an enum; printing it directly showed the
    // enum member name ("HighTemperature") rather than something a user reads.
    function perfDegradationToString(p: int): string {
        switch (p) {
        case PerformanceDegradationReason.HighTemperature:
            return qsTr("The device is too hot");
        case PerformanceDegradationReason.LapDetected:
            return qsTr("The device is on a lap");
        default:
            return qsTr("Unknown reason");
        }
    }

    width: Math.max(300 * scaleOffset, _isSidebarOpen ? (Visibilities.sidebarWidthFor(Tokens.sizes.sidebar.width) * scaleOffset) - Tokens.padding.extraLargeIncreased : 0)
    spacing: Tokens.spacing.medium * scaleOffset

    StyledText {
        Layout.topMargin: Tokens.padding.medium * root.scaleOffset
        Layout.leftMargin: Tokens.padding.small * root.scaleOffset
        text: qsTr("Battery")
        font.weight: 500
        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
    }

    StyledRect {
        Layout.fillWidth: true
        implicitWidth: cardLayout.implicitWidth + Tokens.padding.medium * 2 * root.scaleOffset
        implicitHeight: cardLayout.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
        radius: Tokens.rounding.medium * root.scaleOffset
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        ColumnLayout {
            id: cardLayout

            width: parent.width - Tokens.padding.medium * 2 * root.scaleOffset
            x: Tokens.padding.medium * root.scaleOffset
            y: Tokens.padding.medium * root.scaleOffset
            spacing: Tokens.spacing.large * root.scaleOffset

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.large * root.scaleOffset

                Item {
                    Layout.preferredWidth: 60 * root.scaleOffset
                    Layout.preferredHeight: 110 * root.scaleOffset
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        id: nub

                        width: 24 * root.scaleOffset
                        height: 10 * root.scaleOffset
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        color: Colours.palette.m3primary
                        radius: Tokens.rounding.small

                        Rectangle {
                            width: parent.width
                            height: parent.radius
                            anchors.bottom: parent.bottom
                            color: parent.color
                        }
                    }

                    Item {
                        id: batteryBody

                        anchors.top: parent.top
                        anchors.topMargin: 8 * root.scaleOffset
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right

                        // clip is rectangular, so at 100% the rotating wave poked out of the
                        // outline's rounded top corners; clip to the outline's shape instead
                        StyledClippingRect {
                            anchors.fill: parent
                            radius: Tokens.rounding.medium * root.scaleOffset

                            // Behind the liquid in primary; the copy inside liquidContainer draws
                            // the part over the charge in onPrimary, so the bolt reads at any level.
                            MaterialIcon {
                                id: bolt

                                anchors.centerIn: parent
                                text: "bolt"
                                visible: !UPower.onBattery
                                color: Colours.palette.m3primary
                                fontStyle.pointSize: Tokens.font.icon.large.pointSize * root.fontScale
                            }

                            Item {
                                id: liquidContainer

                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right

                                height: parent.height * (UPower.displayDevice.isLaptopBattery ? UPower.displayDevice.percentage : 0)

                                Behavior on height {
                                    Anim { type: Anim.FastSpatial }
                                }

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.topMargin: waveLayer.opacity * Math.min(18 * root.scaleOffset, parent.height)
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right

                                    color: Colours.palette.m3primary

                                    bottomLeftRadius: Tokens.rounding.medium - 3
                                    bottomRightRadius: Tokens.rounding.medium - 3
                                    topLeftRadius: height >= batteryBody.height - 3 ? Tokens.rounding.medium - 3 : 0
                                    topRightRadius: height >= batteryBody.height - 3 ? Tokens.rounding.medium - 3 : 0
                                }

                                Item {
                                    id: waveLayer

                                    // The crest swings about 4px either side of the charge level, so
                                    // the wave neither lowers the level nor needs fading out near the
                                    // bottom; the outline clip trims what runs past the body.
                                    anchors.top: parent.top
                                    anchors.topMargin: -4 * root.scaleOffset
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 25 * root.scaleOffset
                                    clip: true

                                    opacity: UPower.onBattery ? 0 : 1

                                    Behavior on opacity { Anim { type: Anim.SlowEffects } }

                                    Rectangle {
                                        width: 140 * root.scaleOffset; height: 140 * root.scaleOffset
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 8 * root.scaleOffset

                                        color: Colours.palette.m3primary
                                        radius: 50 * root.scaleOffset

                                        RotationAnimation on rotation {
                                            loops: Animation.Infinite
                                            from: 0; to: 360
                                            duration: 4000
                                            running: waveLayer.opacity > 0 && Tokens.anim.enabled
                                        }
                                    }
                                }

                                Item {
                                    anchors.fill: parent
                                    clip: true
                                    visible: bolt.visible

                                    MaterialIcon {
                                        x: bolt.x
                                        y: bolt.y - liquidContainer.y
                                        text: bolt.text
                                        color: Colours.palette.m3onPrimary
                                        fontStyle: bolt.fontStyle
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: Colours.palette.m3primary
                            border.width: 3 * root.scaleOffset
                            radius: Tokens.rounding.medium * root.scaleOffset
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacing.small * root.scaleOffset

                    StyledText {
                        text: UPower.displayDevice.isLaptopBattery ? qsTr("%1%").arg(Math.round(UPower.displayDevice.percentage * 100)) : qsTr("N/A")
                        font.pointSize: 28 * root.fontScale
                        font.weight: 600
                    }

                    StyledText {
                        text: {
                            if (!UPower.displayDevice.isLaptopBattery)
                                return qsTr("No battery detected");

                            if (UPower.onBattery)
                                return qsTr("~ %1").arg(Units.formatDurationShort(UPower.displayDevice.timeToEmpty, "Calculating..."));

                            if (UPower.displayDevice.state === UPowerDeviceState.FullyCharged || UPower.displayDevice.percentage >= 1.0)
                                return qsTr("Fully charged!");

                            return qsTr("~ %1").arg(Units.formatDurationShort(UPower.displayDevice.timeToFull, "Calculating..."));
                        }
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    }
                }
            }

            Loader {
                asynchronous: true
                Layout.fillWidth: true

                active: PowerProfiles.degradationReason !== PerformanceDegradationReason.None

                sourceComponent: StyledRect {
                    implicitWidth: child.implicitWidth + Tokens.padding.medium * 2 * root.scaleOffset
                    implicitHeight: child.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset

                    color: Colours.palette.m3error
                    radius: Tokens.rounding.large * root.scaleOffset

                    Column {
                        id: child

                        anchors.centerIn: parent

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Tokens.spacing.small * root.scaleOffset

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "warning"
                                color: Colours.palette.m3onError
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Performance degraded: %1").arg(root.perfDegradationToString(PowerProfiles.degradationReason))
                                color: Colours.palette.m3onError
                                font.pointSize: Tokens.font.mono.medium.pointSize * root.fontScale
                            }
                        }
                    }
                }
            }

            StyledRect {
                id: profiles

                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true

                property string current: {
                    const p = PowerProfiles.profile;
                    if (p === PowerProfile.PowerSaver)
                        return saver.icon;
                    if (p === PowerProfile.Performance)
                        return perf.icon;
                    return balance.icon;
                }

                implicitHeight: Math.max(saver.implicitHeight, balance.implicitHeight, perf.implicitHeight) + Tokens.padding.small * root.scaleOffset

                color: Colours.tPalette.m3surfaceContainer
                radius: Tokens.rounding.full * root.scaleOffset

                StyledRect {
                    id: indicator

                    color: Colours.palette.m3primary
                    radius: Tokens.rounding.full * root.scaleOffset
                    state: profiles.current

                    states: [
                        State {
                            name: saver.icon

                            Fill {
                                item: saver
                            }
                        },
                        State {
                            name: balance.icon

                            Fill {
                                item: balance
                            }
                        },
                        State {
                            name: perf.icon

                            Fill {
                                item: perf
                            }
                        }
                    ]

                    transitions: Transition {
                        AnchorAnim {}
                    }
                }

                Profile {
                    id: saver

                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.extraSmall * root.scaleOffset

                    profile: PowerProfile.PowerSaver
                    icon: "energy_savings_leaf"
                }

                Profile {
                    id: balance

                    anchors.centerIn: parent

                    profile: PowerProfile.Balanced
                    icon: "balance"
                }

                Profile {
                    id: perf

                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.padding.extraSmall * root.scaleOffset

                    profile: PowerProfile.Performance
                    icon: "rocket_launch"
                }
            }
        }
    }

    component Fill: AnchorChanges {
        required property Item item

        target: indicator
        anchors.left: item.left
        anchors.right: item.right
        anchors.top: item.top
        anchors.bottom: item.bottom
    }

    component Profile: Item {
        required property string icon
        required property int profile

        implicitWidth: icon.implicitHeight + Tokens.padding.small * root.scaleOffset
        implicitHeight: icon.implicitHeight + Tokens.padding.small * root.scaleOffset

        StateLayer {
            radius: Tokens.rounding.full * root.scaleOffset
            color: profiles.current === parent.icon ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            onClicked: PowerProfiles.profile = parent.profile
        }

        MaterialIcon {
            id: icon

            anchors.centerIn: parent

            text: parent.icon
            fontStyle.pointSize: Tokens.font.icon.large.pointSize * root.fontScale
            color: profiles.current === text ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
            fill: profiles.current === text ? 1 : 0

            Behavior on fill {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }
}
