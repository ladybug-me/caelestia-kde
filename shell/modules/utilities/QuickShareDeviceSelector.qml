pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.Services.QuickShare
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.components.filedialog
import qs.services

Loader {
    id: root

    required property var props
    required property matrix4x4 deformMatrix

    function closeSelector(): void {
        root.props.quickShareDeviceSelectorOpen = false;
    }

    asynchronous: true
    anchors.fill: parent

    opacity: root.props.quickShareDeviceSelectorOpen ? 1 : 0
    active: opacity > 0

    // The beacon only has to be up while the selector is open.
    onActiveChanged: {
        if (active)
            QuickShareService.startBleWakeupBroadcast();
        else
            QuickShareService.stopBleWakeupBroadcast();
    }

    sourceComponent: DrawerModal {
        deformMatrix: root.deformMatrix
        open: root.props.quickShareDeviceSelectorOpen
        onDismissed: root.closeSelector()

        StyledText {
            text: qsTr("Send a file")
            font: Tokens.font.body.large
        }

        StyledText {
            Layout.fillWidth: true
            text: QuickShareService.nearbyDevices.length === 0 ? qsTr("Looking for nearby devices that have Quick Share open.") : qsTr("Choose a nearby device to send the file to.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            animate: true
        }

        // A user reads an empty list as broken, and the other device's network is the
        // one cause this side cannot see.
        StyledText {
            Layout.fillWidth: true
            visible: QuickShareService.nearbyDevices.length === 0
            text: qsTr("Nearby devices have to be on the same network, which for a phone means the same Wi-Fi")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            animate: true
        }

        StyledListView {
            id: deviceList

            Layout.fillWidth: true
            implicitWidth: 300
            implicitHeight: count > 0 ? Math.min(count * 48, 200) : 0
            visible: count > 0
            clip: true

            model: QuickShareService.nearbyDevices

            delegate: WrapperMouseArea {
                required property var modelData

                width: deviceList.width
                height: 48

                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    fileDialog.targetDeviceId = modelData.id;
                    fileDialog.open();
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        text: "smartphone"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.name
                        font: Tokens.font.body.medium
                        elide: Text.ElideRight
                    }
                }
            }
        }

        RowLayout {
            Layout.topMargin: Tokens.spacing.medium
            Layout.alignment: Qt.AlignRight
            spacing: Tokens.spacing.medium

            TextButton {
                text: qsTr("Cancel")
                type: TextButton.Text
                onClicked: root.closeSelector()
            }
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    FileDialog {
        id: fileDialog

        property string targetDeviceId

        title: qsTr("Select a file to send")
        onAccepted: path => {
            if (fileDialog.targetDeviceId !== "")
                QuickShareService.sendFile(fileDialog.targetDeviceId, path.toString().replace("file://", ""));
            root.closeSelector();
        }
        onRejected: root.closeSelector()
    }
}
