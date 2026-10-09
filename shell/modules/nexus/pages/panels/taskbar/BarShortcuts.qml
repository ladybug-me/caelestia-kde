pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Shortcuts")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Configuration")
        }

        ToggleRow {
            first: true
            text: qsTr("Show labels")
            subtext: qsTr("Show the shortcut labels in the bar")
            checked: Config.bar.shortcuts.showLabels
            onToggled: {
                GlobalConfig.bar.shortcuts.showLabels = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Show apps")
            subtext: qsTr("Show quick-launch app buttons in the widget")
            checked: Config.bar.shortcuts.showApps
            onToggled: {
                GlobalConfig.bar.shortcuts.showApps = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Show system")
            subtext: qsTr("Show system shortcuts (Nexus, Overview, etc.)")
            checked: Config.bar.shortcuts.showSystem
            onToggled: {
                GlobalConfig.bar.shortcuts.showSystem = checked;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("Widget")
        }

        StepperRow {
            first: true
            label: qsTr("Button size")
            subtext: qsTr("Size of the shortcut buttons in the widget")
            value: Config.bar.shortcuts.buttonSize
            from: 24
            to: 64
            stepSize: 2
            onMoved: v => {
                GlobalConfig.bar.shortcuts.buttonSize = Math.round(v);
                GlobalConfig.save();
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Show tooltips")
            subtext: qsTr("Show tooltip with shortcut name on hover")
            checked: Config.bar.shortcuts.showTooltips
            onToggled: {
                GlobalConfig.bar.shortcuts.showTooltips = checked;
                GlobalConfig.save();
            }
        }
    }
}
