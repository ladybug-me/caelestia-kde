pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> layoutTypeItems: [
        MenuItem {
            property int value: 0

            text: qsTr("KDE Grid")
        },
        MenuItem {
            property int value: 1

            text: qsTr("GNOME Grid")
        }
    ]

    readonly property list<MenuItem> easingTypeItems: [
        MenuItem {
            property int value: 0

            text: qsTr("Linear")
        },
        MenuItem {
            property int value: 2

            text: qsTr("Quadratic Out")
        },
        MenuItem {
            property int value: 3

            text: qsTr("Quadratic In-Out")
        },
        MenuItem {
            property int value: 6

            text: qsTr("Cubic Out")
        },
        MenuItem {
            property int value: 10

            text: qsTr("Quartic Out")
        },
        MenuItem {
            property int value: 14

            text: qsTr("Quintic Out")
        },
        MenuItem {
            property int value: 18

            text: qsTr("Sine Out")
        },
        MenuItem {
            property int value: 22

            text: qsTr("Exponential Out")
        },
        MenuItem {
            property int value: 26

            text: qsTr("Circular Out")
        },
        MenuItem {
            property int value: 30

            text: qsTr("Elastic Out")
        },
        MenuItem {
            property int value: 33

            text: qsTr("Back In")
        },
        MenuItem {
            property int value: 34

            text: qsTr("Back Out")
        },
        MenuItem {
            property int value: 38

            text: qsTr("Bounce Out")
        }
    ]

    title: qsTr("Overview")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Activation")
        }
        ToggleRow {
            first: true
            text: qsTr("Enable overview")
            reset: ({ node: GlobalConfig.overview, setting: "enabled" })
            checked: GlobalConfig.overview.enabled
            onToggled: GlobalConfig.overview.enabled = checked
        }
        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Open overview by hovering a corner instead of dragging")
            reset: ({ node: GlobalConfig.overview, setting: "showOnHover" })
            checked: GlobalConfig.overview.showOnHover
            onToggled: GlobalConfig.overview.showOnHover = checked
        }
        StepperRow {
            label: qsTr("Trigger area size")
            last: GlobalConfig.overview.showOnHover
            subtext: qsTr("Size of the corner activation areas in pixels")
            reset: ({ node: GlobalConfig.overview, setting: "hoverThickness" })
            value: GlobalConfig.overview.hoverThickness
            from: 1
            to: 100
            stepSize: 1
            onMoved: v => GlobalConfig.overview.hoverThickness = v
            visible: GlobalConfig.overview.showOnHover
        }
        StepperRow {
            last: !GlobalConfig.overview.showOnHover
            label: qsTr("Drag threshold")
            subtext: qsTr("Distance to drag from corner to open overview")
            reset: ({ node: GlobalConfig.overview, setting: "dragThreshold" })
            value: GlobalConfig.overview.dragThreshold
            from: 10
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.overview.dragThreshold = v
            visible: !GlobalConfig.overview.showOnHover
        }
        SectionHeader {
            text: qsTr("Corners")
        }
        // Enabling a corner takes it off KWin for as long as it stays enabled;
        // whatever KDE had bound there comes back untouched when it's turned
        // off, on shell exit, or on the next start after a crash.
        ToggleRow {
            first: true
            text: qsTr("Top-Left corner")
            reset: ({ node: GlobalConfig.overview, setting: "hoverTopLeft" })
            checked: GlobalConfig.overview.hoverTopLeft
            onToggled: GlobalConfig.overview.hoverTopLeft = checked
        }
        ToggleRow {
            text: qsTr("Top-Right corner")
            reset: ({ node: GlobalConfig.overview, setting: "hoverTopRight" })
            checked: GlobalConfig.overview.hoverTopRight
            onToggled: GlobalConfig.overview.hoverTopRight = checked
        }
        ToggleRow {
            text: qsTr("Bottom-Left corner")
            reset: ({ node: GlobalConfig.overview, setting: "hoverBottomLeft" })
            checked: GlobalConfig.overview.hoverBottomLeft
            onToggled: GlobalConfig.overview.hoverBottomLeft = checked
        }
        ToggleRow {
            last: true
            text: qsTr("Bottom-Right corner")
            reset: ({ node: GlobalConfig.overview, setting: "hoverBottomRight" })
            checked: GlobalConfig.overview.hoverBottomRight
            onToggled: GlobalConfig.overview.hoverBottomRight = checked
        }
        SectionHeader {
            text: qsTr("Behavior")
        }
        SelectRow {
            first: true
            label: qsTr("Window layout style")
            subtext: qsTr("Choose the layout algorithm used in the overview")
            fallbackIcon: "grid_view"
            fallbackText: qsTr("GNOME Grid")
            active: {
                for (let i = 0; i < layoutTypeItems.length; i++) {
                    if (layoutTypeItems[i].value === GlobalConfig.overview.layoutType)
                        return layoutTypeItems[i];
                }
                return layoutTypeItems[1];
            }
            menuItems: layoutTypeItems
            onSelected: item => {
                GlobalConfig.overview.layoutType = item.value
            }
        }
        ToggleRow {
            text: qsTr("Disable wallpaper blur")
            subtext: qsTr("Do not blur the background wallpaper when opening overview")
            reset: ({ node: GlobalConfig.overview, setting: "disableWallpaperBlur" })
            checked: GlobalConfig.overview.disableWallpaperBlur
            onToggled: GlobalConfig.overview.disableWallpaperBlur = checked
        }
        ToggleRow {
            last: true
            text: qsTr("Enable overview blur")
            subtext: qsTr("Enable QuickShell-based blur effect on overview wallpaper")
            reset: ({ node: GlobalConfig.overview, setting: "enableOverviewBlur" })
            checked: GlobalConfig.overview.enableOverviewBlur
            onToggled: GlobalConfig.overview.enableOverviewBlur = checked
        }
        SectionHeader {
            text: qsTr("Animations")
        }
        SelectRow {
            first: true
            label: qsTr("Animation easing type")
            subtext: qsTr("Choose the easing curve for overview animations")
            fallbackIcon: "animation"
            fallbackText: qsTr("Back In")
            active: {
                for (let i = 0; i < easingTypeItems.length; i++) {
                    if (easingTypeItems[i].value === GlobalConfig.overview.easingType)
                        return easingTypeItems[i];
                }
                return easingTypeItems[10];
            }
            menuItems: easingTypeItems
            onSelected: item => {
                GlobalConfig.overview.easingType = item.value
            }
        }
        StepperRow {
            label: qsTr("Base duration")
            subtext: qsTr("Base duration for overview opening/closing in milliseconds")
            reset: ({ node: GlobalConfig.overview, setting: "baseDuration" })
            value: GlobalConfig.overview.baseDuration
            from: 100
            to: 1000
            stepSize: 50
            onMoved: v => GlobalConfig.overview.baseDuration = v
        }
        StepperRow {
            label: qsTr("Blob scale speed")
            subtext: qsTr("Scaling speed modifier for background blobs")
            reset: ({ node: GlobalConfig.overview, setting: "blobScaleSpeed" })
            value: GlobalConfig.overview.blobScaleSpeed
            from: 0.1
            to: 5.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.overview.blobScaleSpeed = v
        }
        StepperRow {
            label: qsTr("Wallpaper fade speed")
            subtext: qsTr("Fade speed modifier for the wallpaper")
            reset: ({ node: GlobalConfig.overview, setting: "wallpaperFadeSpeed" })
            value: GlobalConfig.overview.wallpaperFadeSpeed
            from: 0.1
            to: 5.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.overview.wallpaperFadeSpeed = v
        }
        StepperRow {
            last: true
            label: qsTr("Grid fade speed")
            subtext: qsTr("Fade speed modifier for the window grid")
            reset: ({ node: GlobalConfig.overview, setting: "gridFadeSpeed" })
            value: GlobalConfig.overview.gridFadeSpeed
            from: 0.1
            to: 5.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.overview.gridFadeSpeed = v
        }
    }
}
