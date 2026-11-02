pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    required property DrawerVisibilities visibilities
    property bool expanded: false

    readonly property real collapsedHeight: header.implicitHeight + Tokens.padding.large * 2
    readonly property real expandedHeight: header.implicitHeight + content.spacing + bodyLayout.implicitHeight + Tokens.padding.large * 2
    readonly property real nonAnimHeight: root.expanded ? expandedHeight : collapsedHeight

    /// The duration as it is typed, so the field, the button and Enter all ask the same
    /// question of the same string.
    readonly property int typedSeconds: Timers.parseDuration(durationField.text)

    function begin(seconds: int): void {
        if (seconds <= 0)
            return;

        Timers.start(seconds, messageField.text);
        durationField.text = "";
        messageField.text = "";
    }

    function beginTyped(): void {
        root.begin(root.typedSeconds);
    }

    Layout.fillWidth: true
    implicitHeight: nonAnimHeight
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    Behavior on implicitHeight {
        Anim {}
    }

    Connections {
        function onUtilitiesChanged(): void {
            if (!root.visibilities.utilities)
                root.expanded = false;
        }

        target: root.visibilities
    }

    StateLayer {
        anchors.fill: parent
        radius: root.radius
        onClicked: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: content

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            id: header

            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: icon.implicitHeight + Tokens.padding.large

                radius: Tokens.rounding.full
                color: Timers.count > 0 ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: "timer"
                    color: Timers.count > 0 ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Timers")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Timers.count === 0 ? qsTr("Nothing running") : qsTr("%1 running").arg(Timers.count)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            StyledText {
                visible: Timers.pinnedTimer !== null
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.rightMargin: Tokens.spacing.medium
                Layout.preferredWidth: Math.max(84, implicitWidth)
                horizontalAlignment: Text.AlignRight
                text: Timers.pinnedTimer ? Units.formatDuration(Timers.remaining(Timers.pinnedTimer)) : ""
                color: Colours.palette.m3primary
                font: Tokens.font.title.large

                Component.onCompleted: font.features = { "tnum": 1 }
            }
        }

        ColumnLayout {
            id: bodyLayout

            Layout.fillWidth: true
            visible: opacity > 0
            opacity: root.expanded ? 1 : 0
            spacing: Tokens.spacing.small

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Repeater {
                model: Timers.list

                delegate: StyledRect {
                    id: timerRow

                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: timerLayout.implicitHeight + Tokens.padding.small * 2

                    radius: Tokens.rounding.medium
                    color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

                    RowLayout {
                        id: timerLayout

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.small
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: Units.formatDuration(Timers.remaining(timerRow.modelData))
                            font: Tokens.font.title.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: timerRow.modelData.message || qsTr("Timer")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        IconButton {
                            id: pinBtn

                            icon: "push_pin"
                            isToggle: true
                            checked: Timers.pinnedId === timerRow.modelData.id
                            onClicked: {
                                Timers.pin(timerRow.modelData.id);
                                pinBtn.internalChecked = Timers.pinnedId === timerRow.modelData.id;
                            }
                            Accessible.name: checked ? qsTr("Unpin this timer") : qsTr("Pin this timer")
                        }

                        IconButton {
                            icon: "close"
                            onClicked: Timers.cancel(timerRow.modelData.id)
                            Accessible.name: qsTr("Cancel this timer")
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall
                spacing: Tokens.spacing.small

                StyledTextField {
                    id: durationField

                    Layout.preferredWidth: 84
                    horizontalAlignment: TextInput.AlignHCenter
                    placeholderText: qsTr("25m")
                    onAccepted: root.beginTyped()
                }

                StyledTextField {
                    id: messageField

                    Layout.fillWidth: true
                    horizontalAlignment: TextInput.AlignLeft
                    placeholderText: qsTr("What is it for?")
                    onAccepted: root.beginTyped()
                }

                IconButton {
                    icon: "play_arrow"
                    enabled: root.typedSeconds > 0
                    onClicked: root.beginTyped()
                    Accessible.name: qsTr("Start the timer")
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: [5, 10, 25, 45]

                    delegate: TextButton {
                        required property int modelData

                        text: qsTr("%1m").arg(modelData)
                        type: TextButton.Tonal
                        onClicked: root.begin(modelData * 60)
                    }
                }
            }
        }
    }
}
