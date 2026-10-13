pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.bar
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property bool indicatorEnabled: BarWidgets.isEnabled(GlobalConfig.bar, "updateIndicator")

    title: qsTr("Updates")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Show update indicator")
            subtext: qsTr("Always-visible icon in the taskbar that changes when a Caelestia update is available")
            checked: root.indicatorEnabled
            // Custom reset: enabled state lives in bar.entries, default is true
            reset: ({
                customGet: () => root.indicatorEnabled,
                customDef: true,
                customSet: v => BarWidgets.setEnabled(GlobalConfig.bar, "updateIndicator", v)
            })
            onToggled: BarWidgets.setEnabled(GlobalConfig.bar, "updateIndicator", checked)
        }

        ToggleRow {
            last: true
            text: qsTr("Enable update checking")
            subtext: qsTr("Enables the update indicator and periodic checks (every 30 minutes)")
            reset: ({ node: GlobalConfig.general, setting: "checkUpdates" })
            checked: GlobalConfig.general.checkUpdates
            onToggled: GlobalConfig.general.checkUpdates = checked
        }
    }
}
