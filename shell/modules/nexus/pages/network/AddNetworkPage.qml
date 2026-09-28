pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property bool secured: pendingMode ? true : securitySelect.active !== noneItem
    property bool connecting: false
    property bool failed: false
    property bool success: false

    readonly property bool pendingMode: nState.pendingNetworkSsid.length > 0

    function submit(): void {
        const ssid = ssidField.text.trim();
        if (ssid.length === 0) {
            ssidField.isError = true;
            ssidField.forceActiveFocus();
            return;
        }
        if (root.secured && passwordField.text.length < 8) {
            passwordField.isError = true;
            passwordField.forceActiveFocus();
            return;
        }

        root.failed = false;
        root.connecting = true;

        if (root.pendingMode) {
            Nmcli.connectToNetwork(ssid, passwordField.text, "", result => {
                root.connecting = false;
                if (result && result.success) {
                    root.success = true;
                    nState.pendingNetworkSsid = "";
                    root.nState.closeSubPage();
                } else {
                    root.failed = true;
                    passwordField.isError = true;
                    Nmcli.forgetNetwork(ssid);
                }
            });
        } else {
            Nmcli.addHiddenNetwork(ssid, root.secured ? passwordField.text : "", root.secured ? "wpa" : "none", hiddenToggle.checked, result => {
                root.connecting = false;
                if (result && result.success) {
                    root.success = true;
                    root.nState.closeSubPage();
                } else {
                    root.failed = true;
                    if (root.secured)
                        passwordField.isError = true;
                    Nmcli.forgetNetwork(ssid);
                }
            });
        }
    }

    title: root.pendingMode ? qsTr("Enter password") : qsTr("Add network")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        Component.onCompleted: {
            if (nState.pendingNetworkSsid.length > 0) {
                ssidField.text = nState.pendingNetworkSsid;
                passwordField.forceActiveFocus();
            }
        }

        Connections {
            function onSubPageClosed(): void {
                if (root.success) {
                    nState.pendingNetworkSsid = "";
                    return;
                }

                nState.pendingNetworkSsid = "";

                if (!root.pendingMode) {
                    const ssid = ssidField.text.trim();
                    if (ssid)
                        Nmcli.forgetNetwork(ssid);
                }
            }

            target: root.nState
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.extraSmall
            text: root.pendingMode
                ? qsTr("Enter the password for \"%1\".").arg(nState.pendingNetworkSsid)
                : qsTr("Enter the details below to manually connect to a network.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        StyledTextField {
            id: ssidField

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            visible: !root.pendingMode
            enabled: !root.pendingMode
            placeholderText: qsTr("Network name (SSID)")
            supportingText: qsTr("e.g. MyHiddenNetwork")
            leadingIcon: "wifi"
            errorText: qsTr("Network name is required")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onAccepted: root.secured ? passwordField.forceActiveFocus() : root.submit()
        }

        ToggleRow {
            id: hiddenToggle

            visible: !root.pendingMode
            first: true
            text: qsTr("Hidden network")
            subtext: qsTr("Actively probe for a network that doesn't broadcast its name")
            checked: !root.pendingMode
        }

        SelectRow {
            id: securitySelect

            visible: !root.pendingMode
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: !root.secured
            label: qsTr("Security")
            fallbackText: qsTr("WPA/WPA2/WPA3 Personal")
            fallbackIcon: "lock"

            menuItems: [
                MenuItem {
                    icon: "lock"
                    text: qsTr("WPA/WPA2/WPA3 Personal")
                },
                MenuItem {
                    id: noneItem

                    icon: "lock_open"
                    text: qsTr("None (open)")
                }
            ]

            Behavior on bottomLeftRadius {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on bottomRightRadius {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.bottomMargin: root.secured ? 0 : -parent.spacing
            implicitHeight: root.secured ? passwordField.implicitHeight : 0
            opacity: root.secured ? 1 : 0

            Behavior on Layout.bottomMargin {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on implicitHeight {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            StyledTextField {
                id: passwordField

                anchors.left: parent.left
                anchors.right: parent.right

                enabled: root.secured
                placeholderText: qsTr("Password")
                leadingIcon: "key"
                echoMode: TextInput.Password
                supportingText: qsTr("WPA passwords are at least 8 characters")
                errorText: root.failed ? qsTr("Connection failed — check the password") : qsTr("Password must be at least 8 characters")

                onAccepted: root.submit()
            }
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

            ButtonBase {
                id: connectBtn

                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                stateLayer.disabled: root.connecting || ssidField.text.trim().length === 0

                implicitWidth: connectMetrics.width + Tokens.padding.extraLarge * 2
                implicitHeight: connectMetrics.height + Tokens.padding.medium * 2

                onClicked: {
                    if (!root.connecting && ssidField.text.trim().length > 0)
                        root.submit();
                }

                TextMetrics {
                    id: connectMetrics

                    text: qsTr("Connect")
                    font: connectBtn.font
                }

                AnimLoader {
                    id: connectContent

                    anchors.centerIn: parent
                    sourceComp: root.connecting ? connectLoadingComp : connectTextComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: connectLoadingComp

                    LoadingIndicator {
                        implicitSize: Math.round(Tokens.font.body.medium.pointSize * 1.4)
                        color: connectBtn.onColour
                    }
                }

                Component {
                    id: connectTextComp

                    StyledText {
                        text: connectMetrics.text
                        font: connectBtn.font
                        color: connectBtn.onColour
                    }
                }
            }
        }
    }
}
