pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    isSubPage: true
    title: qsTr("Video Wallpapers")

    readonly property bool isHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Pause video wallpapers")
            checked: Config.background.videoWallpaperPaused
            onToggled: GlobalConfig.background.videoWallpaperPaused = checked
        }

        ToggleRow {
            text: qsTr("Enable video audio")
            checked: Config.background.videoWallpaperSoundEnabled
            onToggled: GlobalConfig.background.videoWallpaperSoundEnabled = checked
        }

        ToggleRow {
            text: qsTr("Pause video on fullscreen")
            visible: root.isHyprland
            checked: Config.background.videoWallpaperPauseOnFullscreen
            onToggled: GlobalConfig.background.videoWallpaperPauseOnFullscreen = checked
        }

        ToggleRow {
            text: qsTr("Pause video on tiled windows")
            visible: root.isHyprland
            checked: Config.background.videoWallpaperPauseOnTiled
            onToggled: GlobalConfig.background.videoWallpaperPauseOnTiled = checked
        }

        ToggleRow {
            text: qsTr("Pause video on all displays")
            checked: Config.background.videoWallpaperPauseOnAllDisplays
            onToggled: GlobalConfig.background.videoWallpaperPauseOnAllDisplays = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Mute video when media plays")
            checked: Config.background.videoWallpaperMuteOnMedia
            onToggled: GlobalConfig.background.videoWallpaperMuteOnMedia = checked
        }
    }
}
