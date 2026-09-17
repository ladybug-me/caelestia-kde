pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.utils
import qs.modules.launcher.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Apps")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Default applications
        SectionHeader {
            first: true
            text: qsTr("Default applications")
        }

        ToggleRow {
            id: systemDefaultsToggle

            first: true
            text: qsTr("Force System Defaults (xdg-open)")
            subtext: qsTr("Override applications to use KDE system defaults")
            
            checked: GlobalConfig.general.apps.audio.join(" ") === "xdg-open" &&
                     GlobalConfig.general.apps.playback.join(" ") === "xdg-open" &&
                     GlobalConfig.general.apps.explorer.join(" ") === "xdg-open"

            onToggled: {
                if (checked) {
                    GlobalConfig.general.apps.audio = ["xdg-open"];
                    GlobalConfig.general.apps.playback = ["xdg-open"];
                    GlobalConfig.general.apps.explorer = ["xdg-open"];
                } else {
                    GlobalConfig.general.apps.audio = ["pavucontrol"];
                    GlobalConfig.general.apps.playback = ["mpv"];
                    GlobalConfig.general.apps.explorer = ["thunar"];
                }
            }
        }

        DefaultRow {
            enabled: !systemDefaultsToggle.checked
            icon: "terminal"
            label: qsTr("Terminal")
            status: GlobalConfig.general.apps.terminal.join(" ")
            hideSystemDefault: true
            onSelected: app => GlobalConfig.general.apps.terminal = app.command
        }

        DefaultRow {
            enabled: !systemDefaultsToggle.checked
            icon: "volume_up"
            label: qsTr("Audio")
            status: GlobalConfig.general.apps.audio.join(" ")
            onSelected: app => GlobalConfig.general.apps.audio = app.command
        }

        DefaultRow {
            enabled: !systemDefaultsToggle.checked
            icon: "play_circle"
            label: qsTr("Media playback")
            status: GlobalConfig.general.apps.playback.join(" ")
            onSelected: app => GlobalConfig.general.apps.playback = app.command
        }

        DefaultRow {
            enabled: !systemDefaultsToggle.checked
            last: true
            icon: "folder"
            label: qsTr("File manager")
            status: GlobalConfig.general.apps.explorer.join(" ")
            onSelected: app => GlobalConfig.general.apps.explorer = app.command
        }

        // Library
        SectionHeader {
            text: qsTr("Library")
        }

        NavRow {
            first: true
            last: true
            icon: "apps"
            label: qsTr("All apps")
            status: qsTr("Browse installed apps, set favorites and hidden")
            onClicked: root.nState.openSubPage(1)
        }
    }

    component DefaultRow: PopupRow {
        id: row

        property bool hideSystemDefault: false

        readonly property int popupHeight: root.flickable.height - y + root.flickable.contentY - Tokens.padding.large - Tokens.padding.extraExtraLarge

        signal selected(app: var)

        keepPopupAsChild: {
            if (root.nState.animatingContainer || root.opacity < 1)
                return true;

            let p = root.parent;
            while (p && p.objectName !== "PageContainer")
                p = p.parent;
            return p?.opacity < 1;
        }
        popup.topMovement: Math.max(Tokens.sizes.nexus.minPopupHeight - popupHeight, Tokens.padding.large)

        Loader {
            anchors.centerIn: parent
            active: row.popup.animDriver > 0

            sourceComponent: VerticalFadeListView {
                id: list

                implicitWidth: Tokens.sizes.nexus.popupWidth
                implicitHeight: CUtils.clamp(row.popupHeight, Tokens.sizes.nexus.minPopupHeight, Tokens.sizes.nexus.maxPopupHeight)

                model: Apps.list
                header: StateLayer {
                    anchors.fill: undefined
                    width: list.width
                    visible: !row.hideSystemDefault
                    implicitHeight: visible ? (itemLayoutHeader.implicitHeight + itemLayoutHeader.anchors.margins * 2) : 0
                    height: implicitHeight
                    radius: Tokens.rounding.small

                    onClicked: {
                        row.popup.open = false;
                        row.selected({ command: ["xdg-open"] });
                    }

                    RowLayout {
                        id: itemLayoutHeader

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        IconImage {
                            asynchronous: false // FIX 759: unsafe with KIconLoader
                            implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                            source: Quickshell.iconPath("system-run", "image-missing")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: qsTr("System Default")
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: qsTr("Uses xdg-open (KDE Default)")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                delegate: StateLayer {
                    id: appItem

                    required property var modelData
                    required property int index

                    anchors.fill: undefined
                    anchors.left: list.contentItem.left
                    anchors.right: list.contentItem.right
                    implicitHeight: itemLayout.implicitHeight + itemLayout.anchors.margins * 2
                    radius: Tokens.rounding.small

                    onClicked: {
                        row.popup.open = false;
                        row.selected(modelData.entry);
                    }

                    RowLayout {
                        id: itemLayout

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        IconImage {
                            asynchronous: false // FIX 759: unsafe with KIconLoader
                            implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                            source: Quickshell.iconPath(appItem.modelData.entry.icon, "image-missing")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: appItem.modelData.name
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: (appItem.modelData.comment || appItem.modelData.genericName) ?? ""
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }
                        }

                        MaterialIcon {
                            visible: Strings.testRegexList(GlobalConfig.launcher.favouriteApps, appItem.modelData.id)
                            text: "favorite"
                            fill: 1
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                        }
                    }
                }
            }
        }
    }
}
