pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
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
            enabled: Wallpapers.hasSkwd
            opacity: enabled ? 1 : 0.5
            onClicked: {
                if (resetBtn.armed) {
                    resetBtn.armed = false;
                    resetArmTimer.stop();
                    Launch.exec(["bash", Quickshell.shellPath("scripts/export-plasma-config.sh"), "skwd"]);
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

        SectionHeader {
            first: true
            text: qsTr("Configuration & Tools")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            InfoRow {
                first: true
                Layout.fillWidth: true
                icon: "info"
                wrapSubtext: true
                label: Wallpapers.hasSkwd ? qsTr("Managed by skwd-wall") : qsTr("skwd-wall not installed")
                subtext: Wallpapers.hasSkwd ? qsTr("Wallpaper settings and effects are configured directly through skwd-wall.") : qsTr("Download and install skwd-wall to enable these settings.")
            }

            NavRow {
                icon: "settings"
                label: qsTr("General Settings")
                status: qsTr("Configure wallpaper engine and display options")
                enabled: Wallpapers.hasSkwd
                opacity: enabled ? 1 : 0.5
                onClicked: root.openSkwd("settings")
            }

            NavRow {
                icon: "tune"
                label: qsTr("Wallpaper Mixer")
                status: qsTr("Blend and layer multiple wallpapers")
                enabled: Wallpapers.hasSkwd
                opacity: enabled ? 1 : 0.5
                onClicked: root.openSkwd("mixer")
            }

            NavRow {
                last: true
                icon: "auto_fix_high"
                label: qsTr("Shaders & Effects")
                status: qsTr("Post-processing, blur, and visual filters")
                enabled: Wallpapers.hasSkwd
                opacity: enabled ? 1 : 0.5
                onClicked: root.openSkwd("effects")
            }
        }

        SectionHeader {
            text: qsTr("Playlists & Automation")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            NavRow {
                first: true
                icon: "slideshow"
                label: qsTr("Playlists & Slideshows")
                status: qsTr("Manage wallpaper playlists and transition intervals")
                enabled: Wallpapers.hasSkwd
                opacity: enabled ? 1 : 0.5
                onClicked: root.openSkwd("playlists")
            }

            NavRow {
                last: true
                icon: "schedule"
                label: qsTr("Schedule & Timers")
                status: qsTr("Time-based wallpaper rules and schedules")
                enabled: Wallpapers.hasSkwd
                opacity: enabled ? 1 : 0.5
                onClicked: root.openSkwd("schedule")
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

