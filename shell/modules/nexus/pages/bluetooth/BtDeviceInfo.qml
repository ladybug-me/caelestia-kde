pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property BluetoothDevice device: nState.selectedBtDevice
    readonly property bool connected: device?.state === BluetoothDeviceState.Connected // qmllint disable unresolved-type
    readonly property bool loading: device?.state === BluetoothDeviceState.Connecting || device?.state === BluetoothDeviceState.Disconnecting // qmllint disable unresolved-type

    readonly property string statusText: {
        if (!device)
            return "";
        let s = connected ? qsTr("Connected") : (device.bonded ? qsTr("Paired") : qsTr("Not paired"));
        if (connected && device.batteryAvailable)
            s += " • " + Math.round(device.battery * 100) + "%";
        return s;
    }

    onDeviceChanged: {
        if (!device)
            nState.closeSubPage();
    }

    title: device?.name ?? qsTr("Device")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: Math.round(root.cappedWidth * 0.7)
            spacing: Tokens.spacing.small

            ButtonBase {
                id: forgetBtn

                fillWidth: true
                shapeMorph: true
                isRound: true

                inactiveColour: Colours.palette.m3errorContainer
                inactiveOnColour: Colours.palette.m3onErrorContainer

                implicitWidth: forgetBtnLayout.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: forgetBtnLayout.implicitHeight + Tokens.padding.medium * 2

                onClicked: {
                    root.device?.forget();
                    root.nState.closeSubPage();
                }

                ColumnLayout {
                    id: forgetBtnLayout

                    anchors.centerIn: parent
                    spacing: 0

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "delete"
                        color: forgetBtn.onColour
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Forget")
                        color: forgetBtn.onColour
                    }
                }
            }

            ButtonBase {
                id: connectBtn

                fillWidth: true
                shapeMorph: true
                isRound: true

                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer
                stateLayer.disabled: root.loading

                implicitWidth: connectBtnContent.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: connectBtnContent.implicitHeight + Tokens.padding.medium * 2

                onClicked: root.device.connected = !root.connected

                AnimLoader {
                    id: connectBtnContent

                    anchors.centerIn: parent
                    sourceComp: root.loading ? loadingComp : textComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: loadingComp

                    LoadingIndicator {
                        implicitSize: connectBtn.height - Tokens.padding.large * 2
                    }
                }

                Component {
                    id: textComp

                    ColumnLayout {
                        spacing: 0

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.connected ? "close" : "add"
                            color: connectBtn.inactiveOnColour
                            fontStyle: Tokens.font.icon.medium
                            animate: true
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.connected ? qsTr("Disconnect") : qsTr("Connect")
                            color: connectBtn.inactiveOnColour
                            animate: true
                        }
                    }
                }
            }
        }

        ToggleRow {
            verticalPadding: Tokens.padding.large
            first: true
            text: qsTr("Trusted")
            subtext: qsTr("Allow this device to connect automatically")
            checked: root.device?.trusted ?? false
            onToggled: {
                if (root.device)
                    root.device.trusted = checked;
            }
        }

        ToggleRow {
            verticalPadding: Tokens.padding.large
            text: qsTr("Reconnect on startup")
            subtext: qsTr("Attempt to connect this device when the shell starts")
            checked: root.device && GlobalConfig.services.bluetoothAutoReconnectDevices.includes(root.device.address)
            onToggled: {
                if (!root.device || !root.device.address)
                    return;
                let list = [...GlobalConfig.services.bluetoothAutoReconnectDevices];
                if (checked) {
                    if (!list.includes(root.device.address)) {
                        list.push(root.device.address);
                        GlobalConfig.services.bluetoothAutoReconnectDevices = list;
                    }
                } else {
                    let idx = list.indexOf(root.device.address);
                    if (idx !== -1) {
                        list.splice(idx, 1);
                        GlobalConfig.services.bluetoothAutoReconnectDevices = list;
                    }
                }
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            verticalPadding: Tokens.padding.large
            text: qsTr("Blocked")
            subtext: qsTr("Prevent this device from connecting")
            checked: root.device?.blocked ?? false
            onToggled: {
                if (root.device)
                    root.device.blocked = checked;
            }
        }

        ToggleRow {
            verticalPadding: Tokens.padding.large
            last: true
            text: qsTr("Wake allowed")
            subtext: qsTr("Allow this device to wake the system")
            checked: root.device?.wakeAllowed ?? false
            onToggled: {
                if (root.device)
                    root.device.wakeAllowed = checked;
            }
        }

        ConnectedRect {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            Layout.fillWidth: true
            implicitHeight: batteryLayout.implicitHeight + Tokens.padding.large * 2
            first: true

            ColumnLayout {
                id: batteryLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Battery")
                    }

                    StyledText {
                        text: root.device?.batteryAvailable ? Math.round(root.device.battery * 100) + "%" : qsTr("Unavailable")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: root.device?.batteryAvailable ?? false
                    visible: active
                    asynchronous: true

                    sourceComponent: StyledProgressBar {
                        implicitHeight: Tokens.padding.medium
                        value: root.device.battery
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: addrLayout.implicitHeight + Tokens.padding.large * 2
            last: true

            RowLayout {
                id: addrLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Address")
                }

                StyledText {
                    text: root.device?.address ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }
    }
}
