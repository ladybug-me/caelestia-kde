pragma ComponentBehavior: Bound

import "../../../../utils/scripts/solartime.js" as Solar
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> autoSchemeItems: [
        MenuItem {
            text: qsTr("Sunrise and sunset")
        },
        MenuItem {
            text: qsTr("Fixed times")
        }
    ]
    readonly property list<string> autoSchemeValues: ["solar", "fixed"]

    readonly property list<MenuItem> modeItems: [
        MenuItem {
            text: qsTr("Light")
            icon: "light_mode"
            value: "light"
        },
        MenuItem {
            text: qsTr("Dark")
            icon: "dark_mode"
            value: "dark"
        }
    ]

    property real intensityPosition: Colours.intensityFraction
    property bool draggingIntensity: false

    /// The hour of an "HH:MM" config value, for the steppers.
    function schemeHour(time: string): int {
        const minutes = Solar.parseTime(time);
        return minutes < 0 ? 0 : Math.floor(minutes / 60);
    }

    function withHour(time: string, hour: int): string {
        const minutes = Solar.parseTime(time);
        const mins = minutes < 0 ? 0 : minutes % 60;
        return `${String(hour).padStart(2, "0")}:${String(mins).padStart(2, "0")}`;
    }

    title: qsTr("Advanced Colors")
    isSubPage: true

    ColumnLayout {
        id: contentLayout

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.medium

        Connections {
            function onIntensityChanged(): void {
                if (!root.draggingIntensity)
                    root.intensityPosition = Colours.intensityFraction;
            }

            target: Colours
        }

        Item {
            Layout.preferredHeight: Tokens.spacing.small
        }

        SectionHeader {
            text: qsTr("Theme Automation")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            ToggleRow {
                first: true
                text: qsTr("Smart color scheme")
                subtext: qsTr("Automatically select color variants and theme mode")
                checked: GlobalConfig.services.smartScheme
                onToggled: GlobalConfig.services.smartScheme = checked
            }

            ToggleRow {
                Layout.topMargin: Tokens.spacing.extraSmall / 2
                text: qsTr("Automatic light and dark")
                subtext: qsTr("Switch the theme mode on a schedule")
                checked: GlobalConfig.services.autoSchemeEnabled
                onToggled: GlobalConfig.services.autoSchemeEnabled = checked
                last: !GlobalConfig.services.autoSchemeEnabled
            }

            SelectRow {
                visible: GlobalConfig.services.autoSchemeEnabled
                Layout.topMargin: Tokens.spacing.extraSmall / 2
                label: qsTr("Schedule")
                subtext: AutoScheme.coords ? qsTr("Sunrise and sunset use your weather location") : qsTr("Set a weather location to use sunrise and sunset")
                menuItems: root.autoSchemeItems
                active: root.autoSchemeItems[Math.max(0, root.autoSchemeValues.indexOf(GlobalConfig.services.autoSchemeMode))]
                onSelected: item => GlobalConfig.services.autoSchemeMode = root.autoSchemeValues[root.autoSchemeItems.indexOf(item)]
                last: GlobalConfig.services.autoSchemeMode !== "fixed"
            }

            StepperRow {
                visible: GlobalConfig.services.autoSchemeEnabled && GlobalConfig.services.autoSchemeMode === "fixed"
                Layout.topMargin: Tokens.spacing.extraSmall / 2
                label: qsTr("Light mode hour")
                subtext: qsTr("Switches at %1").arg(GlobalConfig.services.autoSchemeLightTime)
                value: root.schemeHour(GlobalConfig.services.autoSchemeLightTime)
                from: 0
                to: 23
                onMoved: h => GlobalConfig.services.autoSchemeLightTime = root.withHour(GlobalConfig.services.autoSchemeLightTime, h)
            }

            StepperRow {
                visible: GlobalConfig.services.autoSchemeEnabled && GlobalConfig.services.autoSchemeMode === "fixed"
                Layout.topMargin: Tokens.spacing.extraSmall / 2
                last: true
                label: qsTr("Dark mode hour")
                subtext: qsTr("Switches at %1, also used when sunrise and sunset are unavailable").arg(GlobalConfig.services.autoSchemeDarkTime)
                value: root.schemeHour(GlobalConfig.services.autoSchemeDarkTime)
                from: 0
                to: 23
                onMoved: h => GlobalConfig.services.autoSchemeDarkTime = root.withHour(GlobalConfig.services.autoSchemeDarkTime, h)
            }
        }

        SectionHeader {
            text: qsTr("Theme mode")
        }

        SelectRow {
            first: true
            last: true
            enabled: !GlobalConfig.services.autoSchemeEnabled
            label: qsTr("Mode")
            subtext: enabled ? qsTr("Switch the color scheme between light and dark") : qsTr("Managed by the automatic light and dark schedule")
            menuItems: root.modeItems
            active: root.modeItems.find(i => i.value === (Colours.light ? "light" : "dark"))
            onSelected: item => Colours.setMode(item.value)
        }

        SectionHeader {
            text: qsTr("Palette")
        }

        SliderRow {
            first: true
            last: true
            enabled: Colours.scheme === "dynamic"
            label: qsTr("Color intensity")
            subtext: enabled ? qsTr("Chroma of the wallpaper-derived palette, at 100% by default") : qsTr("%1 keeps its own colors, so this does not apply").arg(Colours.scheme)
            valueLabel: Math.round(value * Colours.maxIntensity * 100) + "%"
            value: root.intensityPosition
            onInteraction: root.draggingIntensity = true
            onMoved: v => {
                if (root.draggingIntensity)
                    root.intensityPosition = v;
            }
            onReleased: v => {
                root.draggingIntensity = false;
                root.intensityPosition = v;
                Colours.setIntensity(v);
            }
        }
    }
}
