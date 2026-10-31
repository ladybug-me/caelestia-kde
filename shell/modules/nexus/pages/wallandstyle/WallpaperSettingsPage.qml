pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string skwdKeybind: KeybindsModel.getKey("skwd-wall")
    property string caelestiaKeybind: KeybindsModel.getKey("wallpaper")
    readonly property bool isSkwdOverridden: root.skwdKeybind !== "Meta+X"
    readonly property bool isCaelestiaOverridden: root.caelestiaKeybind !== "Meta+Ctrl+T"

    readonly property list<MenuItem> scalingItems: [
        MenuItem { text: qsTr("Crop") },
        MenuItem { text: qsTr("Fit") },
        MenuItem { text: qsTr("Stretch") }
    ]
    readonly property list<int> scalingValues: [Image.PreserveAspectCrop, Image.PreserveAspectFit, Image.Stretch]
    readonly property list<string> fallbackSettings: [
        "wallpaperFillMode", "wallpaperRecolor", "wallpaperRecolorStrength",
        "slideshowEnabled", "slideshowInterval", "slideshowRandom",
        "videoWallpaperPaused", "videoWallpaperSoundEnabled", "videoWallpaperPauseOnFullscreen",
        "videoWallpaperPauseOnTiled", "videoWallpaperPauseOnAllDisplays", "videoWallpaperMuteOnMedia"
    ]

    function setFallbackOption(setting: string, value: var, saveNow = true): void {
        GlobalConfig.background[setting] = value;
        clearScreenOverrides(setting);
        if (saveNow)
            GlobalConfig.save();
    }

    function clearScreenOverrides(setting: string): void {
        for (const screen of Quickshell.screens) {
            const screenConfig = GlobalConfig.forScreen(screen.name);
            if (screenConfig)
                screenConfig.background.resetOption(setting);
        }
    }

    function resetFallbackSettings(): void {
        const background = GlobalConfig.background;
        for (const setting of root.fallbackSettings) {
            background.resetOption(setting);
            clearScreenOverrides(setting);
        }
        GlobalConfig.save();
    }

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

    function openCaptureDialog(name: string, currentKey: string, targetItem: var): void {
        dialogLoader.active = true;
        dialogLoader.item.shortcutName = name;
        dialogLoader.item.currentKey = currentKey;
        dialogLoader.item.targetItem = targetItem;
        dialogLoader.item.open();
    }

    isSubPage: true
    title: qsTr("Wallpaper Settings")

    headerActions: [
        IconTextButton {
            id: resetBtn

            property bool armed: false

            text: resetBtn.armed ? qsTr("Sure?") : qsTr("Reset settings")
            icon: "restart_alt"
            type: resetBtn.armed ? TextButton.Filled : TextButton.Tonal
            onClicked: {
                if (resetBtn.armed) {
                    resetBtn.armed = false;
                    resetArmTimer.stop();
                    if (Wallpapers.hasSkwd)
                        Launch.exec(["bash", Quickshell.shellPath("scripts/export-plasma-config.sh"), "skwd"]);
                    else
                        root.resetFallbackSettings();
                } else {
                    resetBtn.armed = true;
                    resetArmTimer.start();
                }
            }

            Timer {
                id: resetArmTimer

                interval: 3000
                onTriggered: resetBtn.armed = false
            }
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        Connections {
            function onKeybindsChanged(): void {
                root.skwdKeybind = KeybindsModel.getKey("skwd-wall");
                root.caelestiaKeybind = KeybindsModel.getKey("wallpaper");
            }

            target: KeybindsModel
        }

        Loader {
            id: dialogLoader

            active: false
            sourceComponent: KeyCaptureDialog {
                onConfirm: (name, newKey) => {
                    KeybindsModel.setKey(name, newKey);
                }
                onClear: (name) => {
                    KeybindsModel.setKey(name, "");
                }
                onUnblocked: {
                    dialogLoader.active = false;
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2
            visible: Wallpapers.hasSkwd

            InfoRow {
                first: true
                Layout.fillWidth: true
                icon: "info"
                wrapSubtext: true
                label: qsTr("Managed by skwd-wall")
                subtext: qsTr("Wallpaper settings and effects are configured directly through skwd-wall.")
            }

            NavRow {
                icon: "settings"
                label: qsTr("General Settings")
                status: qsTr("Configure wallpaper engine and display options")
                onClicked: root.openSkwd("settings")
            }

            NavRow {
                icon: "tune"
                label: qsTr("Wallpaper Mixer")
                status: qsTr("Blend and layer multiple wallpapers")
                onClicked: root.openSkwd("mixer")
            }

            NavRow {
                last: true
                icon: "auto_fix_high"
                label: qsTr("Shaders & Effects")
                status: qsTr("Post-processing, blur, and visual filters")
                onClicked: root.openSkwd("effects")
            }
        }

        ColumnLayout {
            visible: !Wallpapers.hasSkwd
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            InfoRow {
                first: true
                Layout.fillWidth: true
                icon: "info"
                wrapSubtext: true
                label: qsTr("Managed by Quickshell")
                subtext: qsTr("The built-in wallpaper renderer is used because skwd-wall is not installed.")
            }

            SelectRow {
                last: true
                label: qsTr("Wallpaper scaling")
                subtext: qsTr("How the wallpaper image fits the screen")
                menuItems: root.scalingItems
                active: root.scalingItems[Math.max(0, root.scalingValues.indexOf(Config.background.wallpaperFillMode))]
                onSelected: item => root.setFallbackOption("wallpaperFillMode", root.scalingValues[root.scalingItems.indexOf(item)])
            }
        }

        SectionHeader {
            visible: !Wallpapers.hasSkwd
            text: qsTr("Shaders & Effects")
        }

        ColumnLayout {
            visible: !Wallpapers.hasSkwd
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            ToggleRow {
                text: qsTr("Recolor wallpaper")
                reset: ({ node: GlobalConfig.background, setting: "wallpaperRecolor" })
                checked: Config.background.wallpaperRecolor
                onToggled: root.setFallbackOption("wallpaperRecolor", checked)
                first: true
            }

            SliderRow {
                last: true
                icon: ""
                label: qsTr("Recolor strength")
                valueLabel: Math.round(value * 100) + "%"
                reset: ({ node: GlobalConfig.background, setting: "wallpaperRecolorStrength" })
                value: Config.background.wallpaperRecolorStrength
                enabled: Config.background.wallpaperRecolor
                onMoved: v => root.setFallbackOption("wallpaperRecolorStrength", v, false)
                onReleased: () => GlobalConfig.save()
            }
        }

        SectionHeader {
            visible: !Wallpapers.hasSkwd
            text: qsTr("Video Wallpapers")
        }

        ColumnLayout {
            visible: !Wallpapers.hasSkwd
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            ToggleRow {
                text: qsTr("Pause video wallpapers")
                reset: ({ node: GlobalConfig.background, setting: "videoWallpaperPaused" })
                checked: Config.background.videoWallpaperPaused
                onToggled: root.setFallbackOption("videoWallpaperPaused", checked)
                first: true
            }
            ToggleRow {
                text: qsTr("Enable video audio")
                reset: ({ node: GlobalConfig.background, setting: "videoWallpaperSoundEnabled" })
                checked: Config.background.videoWallpaperSoundEnabled
                onToggled: root.setFallbackOption("videoWallpaperSoundEnabled", checked)
            }
            ToggleRow {
                text: qsTr("Pause video on fullscreen")
                reset: ({ node: GlobalConfig.background, setting: "videoWallpaperPauseOnFullscreen" })
                checked: Config.background.videoWallpaperPauseOnFullscreen
                onToggled: root.setFallbackOption("videoWallpaperPauseOnFullscreen", checked)
            }
            ToggleRow {
                text: qsTr("Pause video on tiled windows")
                reset: ({ node: GlobalConfig.background, setting: "videoWallpaperPauseOnTiled" })
                checked: Config.background.videoWallpaperPauseOnTiled
                onToggled: root.setFallbackOption("videoWallpaperPauseOnTiled", checked)
            }
            ToggleRow {
                text: qsTr("Pause video on all displays")
                reset: ({ node: GlobalConfig.background, setting: "videoWallpaperPauseOnAllDisplays" })
                checked: Config.background.videoWallpaperPauseOnAllDisplays
                onToggled: root.setFallbackOption("videoWallpaperPauseOnAllDisplays", checked)
            }
            ToggleRow {
                text: qsTr("Mute video when media plays")
                reset: ({ node: GlobalConfig.background, setting: "videoWallpaperMuteOnMedia" })
                checked: Config.background.videoWallpaperMuteOnMedia
                onToggled: root.setFallbackOption("videoWallpaperMuteOnMedia", checked)
                last: true
            }
        }

        SectionHeader {
            text: qsTr("Playlists & Automation")
        }

        ColumnLayout {
            visible: Wallpapers.hasSkwd
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            NavRow {
                first: true
                icon: "slideshow"
                label: qsTr("Playlists & Slideshows")
                status: qsTr("Manage wallpaper playlists and transition intervals")
                visible: Wallpapers.hasSkwd
                onClicked: root.openSkwd("playlists")
            }

            NavRow {
                last: true
                icon: "schedule"
                label: qsTr("Schedule & Timers")
                status: qsTr("Time-based wallpaper rules and schedules")
                visible: Wallpapers.hasSkwd
                onClicked: root.openSkwd("schedule")
            }
        }

        ColumnLayout {
            visible: !Wallpapers.hasSkwd
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            ToggleRow {
                text: qsTr("Wallpaper slideshow")
                reset: ({ node: GlobalConfig.background, setting: "slideshowEnabled" })
                checked: Config.background.slideshowEnabled
                onToggled: root.setFallbackOption("slideshowEnabled", checked)
                first: true
            }

            SliderRow {
                icon: ""
                label: qsTr("Slideshow interval")
                valueLabel: qsTr("%1 min").arg(Math.max(1, Math.round(value * 60)))
                reset: ({ node: GlobalConfig.background, setting: "slideshowInterval" })
                value: Config.background.slideshowInterval
                enabled: Config.background.slideshowEnabled
                onMoved: v => root.setFallbackOption("slideshowInterval", v, false)
                onReleased: () => GlobalConfig.save()
            }

            ToggleRow {
                text: qsTr("Random order")
                reset: ({ node: GlobalConfig.background, setting: "slideshowRandom" })
                checked: Config.background.slideshowRandom
                onToggled: root.setFallbackOption("slideshowRandom", checked)
                last: true
            }
        }

        SectionHeader {
            text: qsTr("Shortcuts")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            ShortcutRow {
                first: true
                actionName: "skwd-wall"
                label: qsTr("skwd-wall")
                status: qsTr("Launch skwd-wall wallpaper changer")
                keybind: root.skwdKeybind
                isOverridden: root.isSkwdOverridden
                isShell: true
                enabled: Wallpapers.hasSkwd
                opacity: enabled ? 1 : 0.5
                onAddClicked: target => root.openCaptureDialog("skwd-wall", root.skwdKeybind, target)
                onKeybindEdited: newKey => KeybindsModel.setKey("skwd-wall", newKey)
                onResetClicked: KeybindsModel.resetKey("skwd-wall")
            }

            ShortcutRow {
                last: true
                actionName: "wallpaper"
                label: qsTr("Caelestia")
                status: qsTr("Launch Caelestia wallpaper changer")
                keybind: root.caelestiaKeybind
                isOverridden: root.isCaelestiaOverridden
                isShell: true
                onAddClicked: target => root.openCaptureDialog("wallpaper", root.caelestiaKeybind, target)
                onKeybindEdited: newKey => KeybindsModel.setKey("wallpaper", newKey)
                onResetClicked: KeybindsModel.resetKey("wallpaper")
            }
        }
    }
}

