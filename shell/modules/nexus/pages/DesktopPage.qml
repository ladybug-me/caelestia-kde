pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Services
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> iconSizeItems: [
        MenuItem {
            text: qsTr("Small")
            value: 48
        },
        MenuItem {
            text: qsTr("Medium")
            value: 64
        },
        MenuItem {
            text: qsTr("Large")
            value: 80
        },
        MenuItem {
            text: qsTr("Huge")
            value: 96
        }
    ]

    title: qsTr("Desktop & Tiling")

    ColumnLayout {
        property bool showTilingLogout: false
        property bool isTilingEnabled: Config.general.krohnkiteEnabled

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Show KDE Desktop")
            subtext: qsTr("Disable Caelestia desktop and use native Plasma 6 desktop instead")
            checked: !Config.background.wallpaperEnabled
            onToggled: { 
                GlobalConfig.background.wallpaperEnabled = !checked; 
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                    if (sConf) sConf.background.resetOption("wallpaperEnabled");
                }
                GlobalConfig.save(); 
            }
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            text: qsTr("Show Desktop Icons")
            subtext: qsTr("Enable icons for Caelestia desktop")
            checked: Config.background.desktopIconsEnabled
            onToggled: { 
                GlobalConfig.background.desktopIconsEnabled = checked; 
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                    if (sConf) sConf.background.resetOption("desktopIconsEnabled");
                }
                GlobalConfig.save(); 
            }
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            text: qsTr("Material You Icons")
            subtext: qsTr("Override the KDE icon theme for desktop icons only")
            checked: Config.background.materialYouIconsEnabled
            onToggled: {
                GlobalConfig.background.materialYouIconsEnabled = checked;
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                    if (sConf) sConf.background.resetOption("materialYouIconsEnabled");
                }
                GlobalConfig.save();
            }
            enabled: Config.background.desktopIconsEnabled
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            text: qsTr("Vibrant Icons")
            subtext: qsTr("Boost saturation of Material You icons for extra vibrancy")
            checked: Config.background.materialYouIconsVibrant
            onToggled: {
                GlobalConfig.background.materialYouIconsVibrant = checked;
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                    if (sConf) sConf.background.resetOption("materialYouIconsVibrant");
                }
                GlobalConfig.save();
            }
            enabled: Config.background.desktopIconsEnabled && Config.background.materialYouIconsEnabled
        }

        SelectRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            label: qsTr("Desktop Icon Size")
            subtext: qsTr("Ctrl+scroll on the desktop also changes it")
            menuItems: root.iconSizeItems
            active: root.iconSizeItems.find(i => i.value === DesktopLayout.iconSize) ?? root.iconSizeItems[1]
            enabled: Config.background.desktopIconsEnabled
            onSelected: item => DesktopLayout.setIconSize(item.value)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            text: qsTr("Arrange Icons Automatically")
            subtext: qsTr("Keep desktop icons packed; dragging one reorders the rest")
            checked: DesktopLayout.autoArrange
            onToggled: DesktopLayout.setAutoArrange(checked)
            enabled: Config.background.desktopIconsEnabled
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            text: qsTr("Magic Lamp Minimize")
            subtext: qsTr("Enable the magic lamp effect when minimizing windows")
            checked: Config.general.magicLampEnabled
            onToggled: {
                GlobalConfig.general.magicLampEnabled = checked;
                GlobalConfig.save();
                Quickshell.execDetached(["bash", "-c", `
                    kwriteconfig6 --file kwinrc --group "Plugins" --key "magiclampEnabled" "${checked ? 'true' : 'false'}" 2>/dev/null || true
                    if [[ "${checked ? 'true' : 'false'}" == "true" ]]; then
                        kwriteconfig6 --file kwinrc --group "Plugins" --key "squashEnabled" "false" 2>/dev/null || true
                        qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "squash" 2>/dev/null || true
                        qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "magiclamp" 2>/dev/null || true
                    else
                        qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "magiclamp" 2>/dev/null || true
                    fi
                    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
                `]);
            }
        }

        NavRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            icon: "view_quilt"
            label: qsTr("Window Tiling")
            status: Config.general.krohnkiteEnabled ? qsTr("Enabled (Krohnkite)") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(3)
        }

        NavRow {
            icon: "extension"
            label: qsTr("Desktop Addons")
            status: qsTr("Clock, Shapes, Lyrics, Visualiser")
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            last: true
            icon: "menu_open"
            label: qsTr("Right Click Menu")
            status: qsTr("Configure desktop right click menu")
            onClicked: root.nState.openSubPage(2)
        }
    }
}
