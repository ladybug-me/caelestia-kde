pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    isSubPage: true
    title: qsTr("Wallpaper Settings")

    readonly property list<MenuItem> scalingItems: [
        MenuItem { text: qsTr("Crop") },
        MenuItem { text: qsTr("Fit") },
        MenuItem { text: qsTr("Stretch") }
    ]

    readonly property list<int> scalingValues: [Image.PreserveAspectCrop, Image.PreserveAspectFit, Image.Stretch]

    function scaleKeyToIndex(key: int): int {
        if (key === Image.PreserveAspectFit) return 1;
        if (key === Image.Stretch) return 2;
        return 0;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.padding.large
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            SelectRow {
                first: true
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                label: qsTr("Wallpaper scaling")
                subtext: qsTr("How the wallpaper image fits the screen")
                menuItems: root.scalingItems
                active: root.scalingItems[root.scaleKeyToIndex(Config.background.wallpaperFillMode)]
                onSelected: item => {
                    let fillMode = root.scalingValues[root.scalingItems.indexOf(item)];
                    GlobalConfig.background.wallpaperFillMode = fillMode;
                    for (let i = 0; i < Quickshell.screens.length; i++) {
                        let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                        if (sConf) sConf.background.resetOption("wallpaperFillMode");
                    }
                    GlobalConfig.save();
                }
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                text: qsTr("Recolor wallpaper")
                subtext: qsTr("Tint the wallpaper to match static color schemes")
                checked: Config.background.wallpaperRecolor
                onToggled: { 
                    GlobalConfig.background.wallpaperRecolor = checked; 
                    for (let i = 0; i < Quickshell.screens.length; i++) {
                        let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                        if (sConf) sConf.background.resetOption("wallpaperRecolor");
                    }
                    GlobalConfig.save(); 
                }
                enabled: Config.background.wallpaperEnabled
            }

            SliderRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
                Layout.fillWidth: true
                last: true
                icon: ""
                label: qsTr("Recolor strength")
                valueLabel: Math.round(value * 100) + "%"
                value: Config.background.wallpaperRecolorStrength
                enabled: Config.background.wallpaperRecolor && Config.background.wallpaperEnabled
                onMoved: v => GlobalConfig.background.wallpaperRecolorStrength = v
            }
        }
    }
}
