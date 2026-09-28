pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string switcherKeybind: KeybindsModel.getKey("windowSwitcher")
    property string switcherReverseKeybind: KeybindsModel.getKey("windowSwitcherReverse")
    readonly property bool isSwitcherOverridden: root.switcherKeybind !== "Alt+Tab"
    readonly property bool isSwitcherReverseOverridden: root.switcherReverseKeybind !== "Alt+Shift+Tab"

    function openCaptureDialog(name: string, currentKey: string, targetItem: var): void {
        dialogLoader.active = true;
        dialogLoader.item.shortcutName = name;
        dialogLoader.item.currentKey = currentKey;
        dialogLoader.item.targetItem = targetItem;
        dialogLoader.item.open();
    }

    title: qsTr("Window Switcher")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Connections {
            function onKeybindsChanged(): void {
                root.switcherKeybind = KeybindsModel.getKey("windowSwitcher");
                root.switcherReverseKeybind = KeybindsModel.getKey("windowSwitcherReverse");
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
            text: qsTr("General")
        }

        ToggleRow {
            first: true
            last: !Config.tabSwitch.enabled
            text: qsTr("Enable Window Switcher")
            subtext: qsTr("Use Caelestia's window switcher for Alt+Tab")
            checked: Config.tabSwitch.enabled
            onToggled: {
                GlobalConfig.tabSwitch.enabled = checked;
                GlobalConfig.save();
            }
        }

        ShortcutRow {
            visible: Config.tabSwitch.enabled
            actionName: "windowSwitcher"
            label: qsTr("Forward")
            keybind: root.switcherKeybind
            isOverridden: root.isSwitcherOverridden
            isShell: true
            onAddClicked: target => root.openCaptureDialog("windowSwitcher", root.switcherKeybind, target)
            onKeybindEdited: newKey => KeybindsModel.setKey("windowSwitcher", newKey)
            onResetClicked: KeybindsModel.resetKey("windowSwitcher")
        }

        ShortcutRow {
            visible: Config.tabSwitch.enabled
            last: true
            actionName: "windowSwitcherReverse"
            label: qsTr("Backward")
            keybind: root.switcherReverseKeybind
            isOverridden: root.isSwitcherReverseOverridden
            isShell: true
            onAddClicked: target => root.openCaptureDialog("windowSwitcherReverse", root.switcherReverseKeybind, target)
            onKeybindEdited: newKey => KeybindsModel.setKey("windowSwitcherReverse", newKey)
            onResetClicked: KeybindsModel.resetKey("windowSwitcherReverse")
        }

        SectionHeader {
            text: qsTr("Behavior")
        }

        ToggleRow {
            first: true
            text: qsTr("Filter by current desktop")
            subtext: qsTr("Only show windows belonging to the active virtual desktop")
            checked: Config.tabSwitch.currentDesktopOnly
            onToggled: {
                GlobalConfig.tabSwitch.currentDesktopOnly = checked;
                GlobalConfig.save();
                Quickshell.execDetached(["bash", "-c", `
                    kwriteconfig6 --file kwinrc --group "TabBox" --key "DesktopMode" "${checked ? "1" : "0"}"
                    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
                `]);
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Preview window on desktop")
            subtext: qsTr("Highlight and show the window itself on the workspace while cycling Alt+Tab")
            checked: Config.tabSwitch.previewOnDesktop
            onToggled: {
                GlobalConfig.tabSwitch.previewOnDesktop = checked;
                GlobalConfig.save();
                Quickshell.execDetached(["bash", "-c", `
                    kwriteconfig6 --file kwinrc --group "TabBox" --key "HighlightWindows" "${checked ? "true" : "false"}"
                    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
                `]);
            }
        }

        SectionHeader {
            text: qsTr("Display")
        }

        ToggleRow {
            first: true
            text: qsTr("Show minimized windows")
            subtext: qsTr("Include minimized windows in the window switcher")
            checked: Config.tabSwitch.showMinimized
            onToggled: {
                GlobalConfig.tabSwitch.showMinimized = checked;
                GlobalConfig.save();
                Quickshell.execDetached(["bash", "-c", `
                    kwriteconfig6 --file kwinrc --group "TabBox" --key "MinMode" "${checked ? "0" : "1"}"
                    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
                `]);
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Show windows from all screens")
            subtext: qsTr("Include windows from all connected monitors")
            checked: Config.tabSwitch.allScreens
            onToggled: {
                GlobalConfig.tabSwitch.allScreens = checked;
                GlobalConfig.save();
                Quickshell.execDetached(["bash", "-c", `
                    kwriteconfig6 --file kwinrc --group "TabBox" --key "MultiScreenMode" "${checked ? "0" : "1"}"
                    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
                `]);
            }
        }
    }
}

