pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Appearance")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        SectionHeader {
            first: true
            text: qsTr("Wallpaper")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            NavRow {
                first: true
                icon: "wallpaper"
                label: qsTr("Wallpapers")
                status: qsTr("Browse and select wallpapers")
                onClicked: root.nState.openSubPage(1)
            }

            NavRow {
                icon: "cloud_download"
                label: qsTr("Library & Community")
                status: qsTr("Wallhaven, online wallpapers, tags and filters")
                onClicked: root.nState.openSubPage(6)
            }

            NavRow {
                icon: "settings_suggest"
                last: true
                label: qsTr("Wallpaper Settings")
                status: Wallpapers.hasSkwd ? qsTr("Configure wallpaper engine, mixer, and effects") : qsTr("Configure scaling, recoloring, video playback, and slideshows")
                onClicked: root.nState.openSubPage(5)
            }
        }

        SectionHeader {
            text: qsTr("Lock screen")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            NavRow {
                first: true
                last: true
                icon: "lock"
                label: qsTr("Lock screen")
                status: qsTr("Wallpaper sync and lock screen settings")
                onClicked: root.nState.openSubPage(8)
            }
        }

        SectionHeader {
            text: qsTr("Colors")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            NavRow {
                first: true
                icon: "palette"
                label: qsTr("Colors")
                status: qsTr("Caelestia owns color management and not skwd-wall.")
                onClicked: root.nState.openSubPage(3)
            }

            NavRow {
                last: true
                icon: "style"
                label: qsTr("Theme & Effects")
                status: qsTr("Islands, Pitch Black, Transparency")
                onClicked: root.nState.openSubPage(7)
            }
        }
    }
}
