import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import "../../../utilities/toasts/corner.js" as Corner

PageBase {
    id: root

    readonly property list<MenuItem> fullscreenItems: [
        MenuItem {
            text: qsTr("Off")
            icon: "notifications_off"
        },
        MenuItem {
            text: qsTr("Important")
            icon: "priority_high"
        },
        MenuItem {
            text: qsTr("On")
            icon: "notifications"
        }
    ]
    readonly property list<string> fullscreenValues: ["off", "important", "all"]

    readonly property list<MenuItem> cornerItems: [
        MenuItem {
            text: qsTr("Automatic")
            icon: "settings_suggest"
        },
        MenuItem {
            text: qsTr("Top left")
            icon: "north_west"
        },
        MenuItem {
            text: qsTr("Top right")
            icon: "north_east"
        },
        MenuItem {
            text: qsTr("Bottom left")
            icon: "south_west"
        },
        MenuItem {
            text: qsTr("Bottom right")
            icon: "south_east"
        }
    ]
    /// The stored names come from corner.js, which is also what resolves them, so the row
    /// and the layout cannot disagree about what a corner is called.
    readonly property list<string> cornerValues: Corner.VALUES

    title: qsTr("Toasts")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Appearance")
        }

        SelectRow {
            first: true
            label: qsTr("Show in fullscreen")
            subtext: qsTr("Allow toasts over fullscreen apps")
            menuItems: root.fullscreenItems
            active: root.fullscreenItems[Math.max(0, root.fullscreenValues.indexOf(GlobalConfig.utilities.toasts.fullscreen))]
            onSelected: item => GlobalConfig.utilities.toasts.fullscreen = root.fullscreenValues[root.fullscreenItems.indexOf(item)]
        }

        StepperRow {
            label: qsTr("Visible toasts")
            subtext: qsTr("Maximum number shown at once")
            value: GlobalConfig.utilities.maxToasts
            from: 1
            to: 10
            stepSize: 1
            onMoved: value => GlobalConfig.utilities.maxToasts = Math.round(value)
        }

        SelectRow {
            label: qsTr("Corner")
            subtext: qsTr("Where the stack grows from. Automatic keeps the corner the shell has always used")
            menuItems: root.cornerItems
            active: root.cornerItems[Corner.index(GlobalConfig.utilities.toasts.position)]
            onSelected: item => GlobalConfig.utilities.toasts.position = root.cornerValues[root.cornerItems.indexOf(item)]
        }

        ToggleRow {
            text: qsTr("Transparency")
            subtext: qsTr("Apply transparency and blur")
            checked: GlobalConfig.utilities.toasts.transparency
            onToggled: GlobalConfig.utilities.toasts.transparency = checked
        }

        SliderRow {
            last: true
            label: qsTr("Base transparency")
            valueLabel: Math.round(value * 100) + "%"
            value: GlobalConfig.utilities.toasts.transparencyBase
            enabled: GlobalConfig.utilities.toasts.transparency
            onMoved: value => GlobalConfig.utilities.toasts.transparencyBase = value
        }

        SectionHeader {
            text: qsTr("Sound")
        }

        SliderRow {
            first: true
            last: true
            icon: "notifications"
            label: qsTr("Notification volume")
            valueLabel: Math.round(value * 100) + "%"
            value: GlobalConfig.audio.sounds.notificationVolume
            enabled: GlobalConfig.audio.sounds.enabled
            onMoved: value => GlobalConfig.audio.sounds.notificationVolume = value
            onReleased: value => Audio.playNotification()
        }
    }
}
