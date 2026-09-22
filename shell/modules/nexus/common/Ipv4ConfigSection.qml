pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ColumnLayout {
    id: root

    required property string connectionName

    property string ipMethod: "auto"
    property bool ipLoaded: false
    property bool savingIp: false
    property string origMethod: "auto"
    property string origAddress: ""
    property string origGateway: ""
    property string origDns: ""

    readonly property bool showDnsSettings: root.ipMethod === "manual" || root.ipMethod === "auto-dns"
    readonly property bool hasChanges: root.ipLoaded && (root.ipMethod !== root.origMethod || (root.ipMethod === "manual" && (addressField.text.trim() !== root.origAddress || gatewayField.text.trim() !== root.origGateway)) || (root.showDnsSettings && dnsField.text.trim() !== root.origDns))

    function loadIpConfig(): void {
        if (!root.connectionName)
            return;
        Nmcli.getIpv4Config(root.connectionName, cfg => {
            if (!cfg)
                return;
            root.ipMethod = cfg.method;
            methodSelect.active = cfg.method === "manual" ? manualItem : (cfg.method === "auto-dns" ? autoDnsItem : autoItem);
            addressField.text = cfg.address;
            gatewayField.text = cfg.gateway;
            dnsField.text = cfg.dns;
            root.origMethod = cfg.method;
            root.origAddress = cfg.address;
            root.origGateway = cfg.gateway;
            root.origDns = cfg.dns;
            root.ipLoaded = true;
        });
    }

    function saveIpConfig(): void {
        if (!root.connectionName)
            return;

        if (root.ipMethod === "manual") {
            if (!addressField.valid) {
                addressField.isError = true;
                return;
            }
            if (!gatewayField.valid) {
                gatewayField.isError = true;
                return;
            }
        }
        if (root.showDnsSettings && !dnsField.valid) {
            dnsField.isError = true;
            return;
        }

        root.savingIp = true;
        Nmcli.setIpv4Config(root.connectionName, {
            method: root.ipMethod,
            address: addressField.text.trim(),
            gateway: gatewayField.text.trim(),
            dns: dnsField.text.trim()
        }, result => {
            root.savingIp = false;
            if (!(result && result.success)) {
                if (root.ipMethod === "manual")
                    addressField.isError = true;
                else
                    dnsField.isError = true;
            } else {
                root.origMethod = root.ipMethod;
                root.origAddress = addressField.text.trim();
                root.origGateway = gatewayField.text.trim();
                root.origDns = dnsField.text.trim();
            }
        });
    }

    onConnectionNameChanged: {
        root.ipLoaded = false;
        root.loadIpConfig();
    }

    spacing: Tokens.spacing.extraSmall / 2

    Component.onCompleted: root.loadIpConfig()

    SectionHeader {
        text: qsTr("IPv4")
    }

    SelectRow {
        id: methodSelect

        Layout.fillWidth: true
        first: true
        last: root.ipMethod === "auto"
        label: qsTr("IP assignment")
        fallbackText: qsTr("Automatic (DHCP)")
        fallbackIcon: "lan"

        menuItems: [
            MenuItem {
                id: autoItem

                icon: "lan"
                text: qsTr("Automatic (DHCP)")
            },
            MenuItem {
                id: autoDnsItem

                icon: "dns"
                text: qsTr("Automatic, DNS only")
            },
            MenuItem {
                id: manualItem

                icon: "edit"
                text: qsTr("Manual")
            }
        ]

        onSelected: item => root.ipMethod = item === manualItem ? "manual" : (item === autoDnsItem ? "auto-dns" : "auto")

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
        Layout.topMargin: root.showDnsSettings ? Tokens.spacing.large : -parent.spacing
        implicitHeight: root.showDnsSettings ? dnsColumn.implicitHeight : 0
        opacity: root.showDnsSettings ? 1 : 0

        Behavior on Layout.topMargin {
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

        ColumnLayout {
            id: dnsColumn

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: root.ipMethod === "manual" ? Tokens.spacing.large : 0

            Behavior on spacing {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: root.ipMethod === "manual" ? manualDnsColumn.implicitHeight : 0
                opacity: root.ipMethod === "manual" ? 1 : 0

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

                ColumnLayout {
                    id: manualDnsColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Tokens.spacing.large

                    StyledTextField {
                        id: addressField

                        Layout.fillWidth: true
                        placeholderText: qsTr("Address (CIDR)")
                        leadingIcon: "router"
                        supportingText: qsTr("IP and prefix, e.g. 192.168.1.50/24")
                        errorText: qsTr("Enter a valid address in CIDR notation")
                        inputMethodHints: Qt.ImhNoPredictiveText
                        validate: /^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\/(?:3[0-2]|[12]?\d)$/
                    }

                    StyledTextField {
                        id: gatewayField

                        Layout.fillWidth: true
                        placeholderText: qsTr("Gateway")
                        leadingIcon: "exit_to_app"
                        errorText: qsTr("Enter a valid gateway address")
                        inputMethodHints: Qt.ImhNoPredictiveText
                        validate: /^$|^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$/
                    }
                }
            }

            StyledTextField {
                id: dnsField

                Layout.fillWidth: true
                placeholderText: qsTr("DNS servers")
                leadingIcon: "dns"
                supportingText: qsTr("Comma-separated")
                errorText: qsTr("Enter valid DNS server addresses")
                inputMethodHints: Qt.ImhNoPredictiveText
                validate: /^$|^\s*(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\s*,\s*(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d))*\s*$/
            }
        }
    }

    Item {
        Layout.alignment: Qt.AlignRight
        implicitWidth: applyBtn.implicitWidth
        implicitHeight: root.hasChanges || root.savingIp ? applyBtn.implicitHeight : 0
        opacity: root.hasChanges || root.savingIp ? 1 : 0

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

        ButtonBase {
            id: applyBtn

            shapeMorph: true
            isRound: true
            inactiveColour: Colours.palette.m3primary
            inactiveOnColour: Colours.palette.m3onPrimary
            stateLayer.disabled: !root.ipLoaded || root.savingIp

            implicitWidth: applyMetrics.width + Tokens.padding.extraLarge * 2
            implicitHeight: applyMetrics.height + Tokens.padding.medium * 2

            onClicked: {
                if (root.ipLoaded && !root.savingIp)
                    root.saveIpConfig();
            }

            TextMetrics {
                id: applyMetrics

                text: qsTr("Apply")
                font: applyBtn.font
            }

            AnimLoader {
                id: applyContent

                anchors.centerIn: parent
                sourceComp: root.savingIp ? applyLoadingComp : applyTextComp
                outAnimType: Anim.SlowEffects
                inAnimType: Anim.SlowEffects
            }

            Component {
                id: applyLoadingComp

                LoadingIndicator {
                    implicitSize: Math.round(Tokens.font.body.medium.pointSize * 1.4)
                    color: applyBtn.onColour
                }
            }

            Component {
                id: applyTextComp

                StyledText {
                    text: qsTr("Apply")
                    color: applyBtn.onColour
                    animate: true
                }
            }
        }
    }
}
