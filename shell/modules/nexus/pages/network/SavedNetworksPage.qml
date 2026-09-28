pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Saved networks")
    isSubPage: true

    Component.onCompleted: Nmcli.loadSavedConnections(() => {})

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ItemList {
            id: savedList

            showList: true
            first: true
            last: true
            placeholderIcon: "wifi_find"
            placeholderText: qsTr("No saved networks")

            model: ScriptModel {
                values: [...Nmcli.savedConnectionProfiles].sort((a, b) => a.ssid.localeCompare(b.ssid) || a.id.localeCompare(b.id))
            }

            delegate: StateLayer {
                id: saved

                required property int index
                required property var modelData
                readonly property Nmcli.SavedProfile profile: modelData
                readonly property var ap: Nmcli.findNetwork(profile.ssid)
                readonly property bool isActive: profile.active

                anchors.left: savedList.list.contentItem.left
                anchors.right: savedList.list.contentItem.right
                implicitHeight: savedLayout.implicitHeight + savedLayout.anchors.margins * 2
                radius: Tokens.rounding.extraSmall
                topLeftRadius: index === 0 ? Tokens.rounding.extraLarge : radius
                topRightRadius: index === 0 ? Tokens.rounding.extraLarge : radius
                bottomLeftRadius: index === savedList?.list.count - 1 ? Tokens.rounding.extraLarge : radius
                bottomRightRadius: index === savedList?.list.count - 1 ? Tokens.rounding.extraLarge : radius
                anchors.fill: undefined

                onClicked: root.nState.openNetworkDetail(saved.profile.ssid, saved.profile.uuid, true)

                RowLayout {
                    id: savedLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    anchors.leftMargin: Tokens.padding.extraLarge
                    anchors.rightMargin: Tokens.padding.extraLarge
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: saved.ap ? Icons.getNetworkIcon(saved.ap.strength, !["", "none"].includes(saved.profile.security)) : "signal_wifi_off"
                        color: saved.isActive ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: saved.profile.duplicate ? qsTr("%1 (%2)").arg(saved.profile.ssid).arg(saved.profile.disambiguator) : saved.profile.ssid
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                let security;
                                if (saved.ap)
                                    security = saved.ap.security || qsTr("Open");
                                else
                                    security = Nmcli.securityLabel(saved.profile.security) || qsTr("Unknown");
                                if (saved.isActive)
                                    return qsTr("Connected • %1").arg(security);
                                return security;
                            }
                            color: saved.isActive ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "delete"
                        onClicked: Nmcli.forgetNetworkByUuid(saved.profile.uuid)
                    }

                    MaterialIcon {
                        text: "chevron_right"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }
                }
            }
        }
    }
}
