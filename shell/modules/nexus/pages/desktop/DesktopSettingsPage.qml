pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
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

    title: qsTr("Desktop")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Disable Quickshell Desktop")
            subtext: qsTr("Completely disable quickshell desktop features and use plasma desktop.")
            checked: Config.background.disableQuickshellDesktop
            onToggled: {
                GlobalConfig.background.disableQuickshellDesktop = checked;
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                    if (sConf)
                        sConf.background.resetOption("disableQuickshellDesktop");
                }
                GlobalConfig.save();
                DesktopLayout.syncKdeWallpaperLayout(checked ? "folder" : "desktop");
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Show Desktop Icons")
            subtext: qsTr("Enable icons for Caelestia desktop")
            reset: ({
                node: GlobalConfig.background,
                setting: "desktopIconsEnabled"
            })
            checked: Config.background.desktopIconsEnabled
            enabled: !Config.background.disableQuickshellDesktop
            onToggled: {
                GlobalConfig.background.desktopIconsEnabled = checked;
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                    if (sConf)
                        sConf.background.resetOption("desktopIconsEnabled");
                }
                GlobalConfig.save();
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Material You Icons")
            subtext: qsTr("Override the KDE icon theme for desktop icons only")
            reset: ({
                node: GlobalConfig.background,
                setting: "materialYouIconsEnabled"
            })
            checked: Config.background.materialYouIconsEnabled
            enabled: !Config.background.disableQuickshellDesktop && Config.background.desktopIconsEnabled
            onToggled: {
                GlobalConfig.background.materialYouIconsEnabled = checked;
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                    if (sConf)
                        sConf.background.resetOption("materialYouIconsEnabled");
                }
                GlobalConfig.save();
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Vibrant Icons")
            subtext: qsTr("Boost saturation of Material You icons for extra vibrancy")
            reset: ({
                node: GlobalConfig.background,
                setting: "materialYouIconsVibrant"
            })
            checked: Config.background.materialYouIconsVibrant
            enabled: !Config.background.disableQuickshellDesktop && Config.background.desktopIconsEnabled && Config.background.materialYouIconsEnabled
            onToggled: {
                GlobalConfig.background.materialYouIconsVibrant = checked;
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                    if (sConf)
                        sConf.background.resetOption("materialYouIconsVibrant");
                }
                GlobalConfig.save();
            }
        }

        StepperRow {
            label: qsTr("Icon Vibrancy")
            subtext: qsTr("Saturation level of vibrant Material You icons")
            reset: ({
                node: GlobalConfig.background,
                setting: "materialYouIconsVibrancy"
            })
            value: Config.background.materialYouIconsVibrancy
            from: 0.0
            to: 1.0
            stepSize: 0.05
            enabled: !Config.background.disableQuickshellDesktop && Config.background.desktopIconsEnabled && Config.background.materialYouIconsEnabled && Config.background.materialYouIconsVibrant
            onMoved: v => {
                GlobalConfig.background.materialYouIconsVibrancy = v;
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                    if (sConf)
                        sConf.background.resetOption("materialYouIconsVibrancy");
                }
                GlobalConfig.save();
            }
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Desktop Icon Size")
            subtext: qsTr("Ctrl+scroll on the desktop also changes it")
            menuItems: root.iconSizeItems
            active: root.iconSizeItems.find(i => i.value === DesktopLayout.iconSize) ?? root.iconSizeItems[1]
            enabled: !Config.background.disableQuickshellDesktop && Config.background.desktopIconsEnabled
            onSelected: item => DesktopLayout.setIconSize(item.value)
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Arrange Icons Automatically")
            subtext: qsTr("Keep desktop icons packed; dragging one reorders the rest")
            checked: DesktopLayout.autoArrange
            enabled: !Config.background.disableQuickshellDesktop && Config.background.desktopIconsEnabled
            onToggled: DesktopLayout.setAutoArrange(checked)
        }
    }
}
