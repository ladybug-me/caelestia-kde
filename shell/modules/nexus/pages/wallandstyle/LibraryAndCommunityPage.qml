pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    function openSkwd(section: string): void {
        const target = section ? section : "";
        const script =
            'if ! command -v skwd-helm >/dev/null 2>&1; then ' +
            '    command -v skwd-wall-v2 >/dev/null 2>&1 && exec skwd-wall-v2 || exec skwd-wall; ' +
            '    exit 0; ' +
            'fi; ' +
            'if ! skwd-helm ui state >/dev/null 2>&1; then ' +
            '    (command -v skwd-wall-v2 >/dev/null 2>&1 && setsid skwd-wall-v2 </dev/null >/dev/null 2>&1 || setsid skwd-wall </dev/null >/dev/null 2>&1) & ' +
            '    for i in $(seq 1 30); do ' +
            '        sleep 0.1; ' +
            '        if skwd-helm ui state >/dev/null 2>&1; then break; fi; ' +
            '    done; ' +
            'fi; ' +
            'skwd-helm ui show >/dev/null 2>&1 || true; ' +
            'skwd-helm ui dismiss >/dev/null 2>&1 || true; ' +
            (target !== "" ? `skwd-helm ui open "${target}";` : "");

        Launch.exec(["sh", "-c", script]);
    }

    isSubPage: true
    title: qsTr("Community & Online")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            NavRow {
                first: true
                icon: "image_search"
                label: qsTr("Wallhaven")
                status: qsTr("Download wallpapers from Wallhaven")
                onClicked: root.nState.openSubPage(4)
            }

            NavRow {
                last: true
                icon: "cloud_download"
                label: qsTr("Online Wallpapers")
                status: qsTr("Browse and download community wallpapers")
                enabled: Wallpapers.hasSkwd
                opacity: enabled ? 1 : 0.5
                onClicked: root.openSkwd("downloads")
            }
        }

        SectionHeader {
            text: qsTr("Library Management")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            InfoRow {
                first: true
                Layout.fillWidth: true
                visible: !Wallpapers.hasSkwd
                icon: "info"
                wrapSubtext: true
                label: qsTr("skwd-wall not installed")
                subtext: qsTr("Download and install skwd-wall to enable these settings.")
            }

            NavRow {
                first: Wallpapers.hasSkwd
                icon: "label"
                label: qsTr("Tags & Filters")
                status: qsTr("Organize library with custom tags")
                enabled: Wallpapers.hasSkwd
                opacity: enabled ? 1 : 0.5
                onClicked: root.openSkwd("tags")
            }

            NavRow {
                last: true
                icon: "wallpaper"
                label: qsTr("Open skwd-wall")
                status: qsTr("Launch the main wallpaper picker interface")
                enabled: Wallpapers.hasSkwd
                opacity: enabled ? 1 : 0.5
                onClicked: root.openSkwd("")
            }
        }
    }
}
