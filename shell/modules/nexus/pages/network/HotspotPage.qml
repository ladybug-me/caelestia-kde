pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Settings for the Wi-Fi hotspot: the name and password it shares with, and the
// switch that starts and stops it. Reached from the Hotspot row on NetworkPage,
// and the values kept here are the ones the utilities panel's hotspot toggle
// starts the access point with.
PageBase {
    id: root

    readonly property bool changed: ssidField.text.trim() !== GlobalConfig.services.hotspotSsid || passwordField.text !== GlobalConfig.services.hotspotPassword

    property bool busy: false
    property string failure: ""

    function remember(): void {
        GlobalConfig.services.hotspotSsid = ssidField.text.trim();
        GlobalConfig.services.hotspotPassword = passwordField.text;
    }

    function report(result: var): void {
        root.busy = false;
        root.failure = result && result.success ? "" : (result?.error || qsTr("The hotspot could not be started"));
    }

    function enable(): void {
        root.failure = "";
        root.busy = true;
        Nmcli.enableHotspot(GlobalConfig.services.hotspotSsid, GlobalConfig.services.hotspotPassword, result => root.report(result));
    }

    function disable(): void {
        root.failure = "";
        root.busy = true;
        Nmcli.disableHotspot(result => root.report(result));
    }

    function submit(): void {
        if (root.busy)
            return;

        if (!passwordField.valid) {
            passwordField.isError = true;
            passwordField.forceActiveFocus();
            return;
        }

        if (!root.changed) {
            root.nState.closeSubPage();
            return;
        }

        root.remember();

        // A running access point keeps the name and password it started with,
        // so changing them takes it down and brings it back up. The page stays
        // open for that, so a start that goes wrong can be read here.
        if (Nmcli.hotspotEnabled) {
            root.busy = true;
            Nmcli.disableHotspot(() => root.enable());
        } else {
            root.nState.closeSubPage();
        }
    }

    title: qsTr("Hotspot")
    isSubPage: true

    Component.onCompleted: {
        ssidField.text = GlobalConfig.services.hotspotSsid;
        passwordField.text = GlobalConfig.services.hotspotPassword;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.extraSmall
            text: qsTr("Share this machine's connection over Wi-Fi. The hotspot is saved as a connection named \"caelestia-hotspot\", so Plasma's own network applet can see it too.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.extraSmall
            visible: !Nmcli.hotspotSupported
            text: qsTr("No wireless device on this machine can run an access point.")
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        ToggleRow {
            id: hotspotToggle

            first: true
            last: true
            text: qsTr("Hotspot")
            subtext: Nmcli.hotspotEnabled ? qsTr("Sharing as \"%1\"").arg(Nmcli.hotspotSsid) : qsTr("Off")
            enabled: Nmcli.hotspotSupported && !root.busy

            onToggled: {
                // Applying the backend state runs this again, and a toggle that
                // already matches it is not an instruction to try.
                if (root.busy || checked === Nmcli.hotspotEnabled)
                    return;

                if (checked)
                    root.enable();
                else
                    root.disable();
            }

            // The switch reports what the backend is doing rather than what was
            // tapped, so a start that fails puts it back where it was. A Binding
            // survives the switch's own click; a plain binding would not.
            Binding on checked {
                when: !root.busy
                value: Nmcli.hotspotEnabled
            }
        }

        StyledTextField {
            id: ssidField

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium - parent.spacing
            placeholderText: qsTr("Hotspot name (SSID)")
            supportingText: qsTr("Leave empty to use this machine's name, %1").arg(SysInfo.hostname || "caelestia")
            leadingIcon: "wifi_tethering"
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onAccepted: passwordField.forceActiveFocus()
        }

        StyledTextField {
            id: passwordField

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            placeholderText: qsTr("Password")
            supportingText: qsTr("At least 8 characters. Leave empty to share an open network.")
            errorText: qsTr("A password is either empty or at least 8 characters")
            leadingIcon: "key"
            echoMode: TextInput.Password
            validate: text => text.length === 0 || text.length >= 8

            onAccepted: root.submit()
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.extraSmall
            visible: root.failure.length > 0
            text: root.failure
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.spacing.extraSmall - parent.spacing
            spacing: Tokens.spacing.small

            TextButton {
                Layout.fillHeight: true
                isRound: true
                horizontalPadding: Tokens.padding.extraLarge
                type: TextButton.Tonal
                text: qsTr("Cancel")
                onClicked: root.nState.closeSubPage()
            }

            // Save button - swaps to a loading spinner while the hotspot is
            // being started, stopped, or restarted with the new name.
            ButtonBase {
                id: saveBtn

                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                stateLayer.disabled: root.busy

                implicitWidth: saveMetrics.width + Tokens.padding.extraLarge * 2
                implicitHeight: saveMetrics.height + Tokens.padding.medium * 2

                onClicked: {
                    if (!root.busy)
                        root.submit();
                }

                TextMetrics {
                    id: saveMetrics

                    text: qsTr("Save")
                    font: saveBtn.font
                }

                AnimLoader {
                    id: saveContent

                    anchors.centerIn: parent
                    sourceComp: root.busy ? saveLoadingComp : saveTextComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: saveLoadingComp

                    LoadingIndicator {
                        implicitSize: Math.round(Tokens.font.body.medium.pointSize * 1.4)
                        color: saveBtn.onColour
                    }
                }

                Component {
                    id: saveTextComp

                    StyledText {
                        text: saveMetrics.text
                        font: saveBtn.font
                        color: saveBtn.onColour
                    }
                }
            }
        }
    }
}
