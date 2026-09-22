pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property DesktopEntry app: nState.selectedApp
    readonly property bool favouriteByRegex: app && matchedByRegex(GlobalConfig.launcher.favouriteApps, app.id)
    readonly property bool hiddenByRegex: app && matchedByRegex(GlobalConfig.launcher.hiddenApps, app.id)
    readonly property bool pinnedToDockByRegex: app && matchedByRegex(GlobalConfig.bar.dock.pinnedApps, app.id)

    function matchedByRegex(filterList: var, id: string): bool {
        return Array.from(filterList).some(f => Strings.isRegex(f) && Strings.testRegex(f, id));
    }

    onAppChanged: {
        // Auto close when app lost
        if (!app)
            nState.closeSubPage();
    }

    title: qsTr("App info")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.bottomMargin: Tokens.spacing.large
            spacing: Tokens.spacing.large

            IconImage {
                asynchronous: true
                implicitSize: Math.round(Tokens.font.icon.large.pointSize * 3)
                source: WinIcons.sourceFor(root.app, "", root.app?.id ?? "", 0)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.app?.name ?? ""
                    font: Tokens.font.title.medium
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text
                    text: (root.app?.comment || root.app?.genericName) ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Dock
        SectionHeader {
            first: true
            text: qsTr("Taskbar & Dock")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Pin to dock")
            subtext: root.pinnedToDockByRegex ? qsTr("Matched by a regex in pinnedApps - edit the config file to change") : qsTr("Show on the dock even when not running")
            enabled: !root.pinnedToDockByRegex
            checked: root.app && Strings.testRegexList(GlobalConfig.bar.dock.pinnedApps, root.app.id)
            onToggled: {
                const apps = GlobalConfig.bar.dock.pinnedApps ? [...GlobalConfig.bar.dock.pinnedApps] : [];
                GlobalConfig.bar.dock.pinnedApps = checked ? [...apps, root.app.id] : apps.filter(a => a !== root.app.id);
            }
        }

        // Launcher
        SectionHeader {
            text: qsTr("Launcher")
        }

        ToggleRow {
            first: true
            text: qsTr("Favorite")
            subtext: root.favouriteByRegex ? qsTr("Matched by a regex in favouriteApps - edit the config file to change") : qsTr("Pin to the top of the launcher")
            enabled: !root.favouriteByRegex
            checked: root.app && Strings.testRegexList(GlobalConfig.launcher.favouriteApps, root.app.id)
            onToggled: {
                const apps = GlobalConfig.launcher.favouriteApps;
                GlobalConfig.launcher.favouriteApps = checked ? [...apps, root.app.id] : apps.filter(a => a !== root.app.id);
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Hidden")
            subtext: root.hiddenByRegex ? qsTr("Matched by a regex in hiddenApps - edit the config file to change") : qsTr("Hide from the launcher")
            enabled: !root.hiddenByRegex
            checked: root.app && Strings.testRegexList(GlobalConfig.launcher.hiddenApps, root.app.id)
            onToggled: {
                const apps = GlobalConfig.launcher.hiddenApps;
                GlobalConfig.launcher.hiddenApps = checked ? [...apps, root.app.id] : apps.filter(a => a !== root.app.id);
            }
        }

        // Details
        SectionHeader {
            text: qsTr("Details")
        }

        WrapInfoRow {
            id: appId

            first: true
            label: qsTr("App ID")
            value: root.app?.id ?? ""
            labelComp.Layout.preferredWidth: Math.max(labelComp.implicitWidth, command.labelComp.implicitWidth)
        }

        WrapInfoRow {
            id: command

            last: true
            label: qsTr("Command")
            value: (root.app?.command ?? []).join(" ")
            labelComp.Layout.preferredWidth: Math.max(labelComp.implicitWidth, appId.labelComp.implicitWidth)
        }
    }

    component WrapInfoRow: ConnectedRect {
        id: row

        property alias label: label.text
        property alias value: value.text
        readonly property alias labelComp: label

        Layout.fillWidth: true
        implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins * 2

        RowLayout {
            id: rowLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            StyledText {
                id: label

                Layout.alignment: Qt.AlignTop
                font: Tokens.font.body.small
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                id: value

                Layout.fillWidth: true
                Layout.maximumWidth: implicitWidth + 1 // Whyyyyyyyyy
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }
        }
    }
}
