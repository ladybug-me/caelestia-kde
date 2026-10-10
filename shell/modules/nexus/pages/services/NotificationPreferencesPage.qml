import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> fullscreenItems: [
        MenuItem {
            text: qsTr("Off")
            icon: "notifications_off"
        },
        MenuItem {
            text: qsTr("On")
            icon: "notifications"
        }
    ]
    readonly property list<string> fullscreenValues: ["off", "on"]
    readonly property list<MenuItem> monitorItems: [
        MenuItem {
            text: qsTr("All screens")
            icon: "devices"
        },
        MenuItem {
            text: qsTr("Focused screen")
            icon: "desktop_windows"
        }
    ]
    readonly property list<string> monitorValues: ["all", "focused"]
    readonly property list<MenuItem> positionItems: [
        MenuItem {
            text: qsTr("Auto")
            icon: "auto_awesome"
        },
        MenuItem {
            text: qsTr("Top Left")
            icon: "north_west"
        },
        MenuItem {
            text: qsTr("Top Center")
            icon: "north"
        },
        MenuItem {
            text: qsTr("Top Right")
            icon: "north_east"
        },
        MenuItem {
            text: qsTr("Bottom Left")
            icon: "south_west"
        },
        MenuItem {
            text: qsTr("Bottom Center")
            icon: "south"
        },
        MenuItem {
            text: qsTr("Bottom Right")
            icon: "south_east"
        }
    ]
    readonly property list<string> positionValues: ["auto", "top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]

    title: qsTr("Notifications")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Display")
        }

        SelectRow {
            first: true
            label: qsTr("Show in fullscreen")
            subtext: qsTr("Allow notifications over fullscreen apps")
            menuItems: root.fullscreenItems
            active: root.fullscreenItems[Math.max(0, root.fullscreenValues.indexOf(GlobalConfig.notifs.fullscreen))]
            onSelected: item => GlobalConfig.notifs.fullscreen = root.fullscreenValues[root.fullscreenItems.indexOf(item)]
        }

        SelectRow {
            label: qsTr("Display on screen")
            subtext: qsTr("Which screens show notification popups")
            menuItems: root.monitorItems
            active: root.monitorItems[Math.max(0, root.monitorValues.indexOf(GlobalConfig.notifs.monitor))]
            onSelected: item => GlobalConfig.notifs.monitor = root.monitorValues[root.monitorItems.indexOf(item)]
        }

        SelectRow {
            label: qsTr("Position")
            subtext: qsTr("Where notification popups appear")
            menuItems: root.positionItems
            active: root.positionItems[Math.max(0, root.positionValues.indexOf(GlobalConfig.notifs.position))]
            onSelected: item => GlobalConfig.notifs.position = root.positionValues[root.positionItems.indexOf(item)]
        }

        ToggleRow {
            text: qsTr("Expire automatically")
            subtext: qsTr("Dismiss notifications after their timeout")
            checked: GlobalConfig.notifs.expire
            onToggled: GlobalConfig.notifs.expire = checked
        }

        ToggleRow {
            text: qsTr("Open expanded")
            subtext: qsTr("Show notifications expanded by default")
            checked: GlobalConfig.notifs.openExpanded
            reset: ({
                node: GlobalConfig.notifs,
                setting: "openExpanded"
            })
            onToggled: GlobalConfig.notifs.openExpanded = checked
        }

        ToggleRow {
            text: qsTr("Do not disturb while sharing")
            subtext: qsTr("Mute notifications while the screen is being shared or recorded")
            checked: GlobalConfig.utilities.toasts.dndWhileStreaming
            reset: ({
                node: GlobalConfig.utilities.toasts,
                setting: "dndWhileStreaming"
            })
            onToggled: GlobalConfig.utilities.toasts.dndWhileStreaming = checked
        }

        StepperRow {
            label: qsTr("Default timeout")
            subtext: qsTr("Seconds before a notification dismisses")
            value: GlobalConfig.notifs.defaultExpireTimeout / 1000
            from: 1
            to: 60
            stepSize: 1
            onMoved: value => GlobalConfig.notifs.defaultExpireTimeout = Math.round(value * 1000)
        }

        StepperRow {
            label: qsTr("Group preview count")
            subtext: qsTr("Notifications shown before a group collapses")
            value: GlobalConfig.notifs.groupPreviewNum
            from: 1
            to: 10
            stepSize: 1
            onMoved: value => GlobalConfig.notifs.groupPreviewNum = Math.round(value)
        }

        StepperRow {
            label: qsTr("Max popup notifications")
            subtext: qsTr("Only the newest popups are shown; the rest stay in the sidebar")
            value: GlobalConfig.notifs.maxPopups
            from: 0
            to: 30
            stepSize: 1
            onMoved: value => GlobalConfig.notifs.maxPopups = Math.round(value)
        }

        StepperRow {
            last: true
            label: qsTr("Max stored notifications")
            subtext: qsTr("Older notifications are dropped when the limit is reached")
            value: GlobalConfig.notifs.maxNotifs
            from: 20
            to: 2000
            stepSize: 50
            onMoved: value => GlobalConfig.notifs.maxNotifs = Math.round(value)
        }

        SectionHeader {
            text: qsTr("Interaction")
        }

        ToggleRow {
            first: true
            text: qsTr("Click to activate")
            subtext: qsTr("Activate the notification action on click")
            checked: GlobalConfig.notifs.actionOnClick
            onToggled: GlobalConfig.notifs.actionOnClick = checked
        }

        StepperRow {
            label: qsTr("Expand threshold")
            subtext: qsTr("Hover pixels before a docked notification expands")
            value: GlobalConfig.notifs.expandThreshold
            from: 5
            to: 100
            stepSize: 5
            onMoved: value => GlobalConfig.notifs.expandThreshold = Math.round(value)
        }

        StepperRow {
            label: qsTr("Fullscreen timeout")
            subtext: qsTr("Milliseconds a notification stays over a fullscreen app")
            value: GlobalConfig.notifs.fullscreenExpireTimeout / 1000
            from: 1
            to: 30
            stepSize: 1
            onMoved: value => GlobalConfig.notifs.fullscreenExpireTimeout = Math.round(value * 1000)
        }

        SliderRow {
            last: true
            label: qsTr("Clear threshold")
            subtext: qsTr("Swipe distance before a notification is dismissed")
            valueLabel: Math.round(value * 100) + "%"
            value: GlobalConfig.notifs.clearThreshold
            onMoved: value => GlobalConfig.notifs.clearThreshold = value
        }
    }
}