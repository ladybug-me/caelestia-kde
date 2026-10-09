pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Keep Awake")
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
            last: true
            text: qsTr("Show active indicator")
            subtext: qsTr("Show a chip with the activation time when Keep Awake is on")
            checked: Config.bar.keepawake.showActiveChip
            onToggled: {
                GlobalConfig.bar.keepawake.showActiveChip = checked;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("Widget")
        }

        ToggleRow {
            first: true
            text: qsTr("Show tooltip")
            subtext: qsTr("Show tooltip with status on hover")
            checked: Config.bar.keepawake.showTooltip
            onToggled: {
                GlobalConfig.bar.keepawake.showTooltip = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Auto-hide when inactive")
            subtext: qsTr("Hide the widget when Keep Awake is off")
            checked: Config.bar.keepawake.autoHide
            onToggled: {
                GlobalConfig.bar.keepawake.autoHide = checked;
                GlobalConfig.save();
            }
        }
    }
}
