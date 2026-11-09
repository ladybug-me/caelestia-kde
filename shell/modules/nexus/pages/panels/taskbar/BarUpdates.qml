pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.modules.bar
import qs.modules.nexus
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property bool indicatorEnabled: BarWidgets.isEnabled(GlobalConfig.bar, "updateIndicator")

    readonly property bool checkingOff: !GlobalConfig.general.checkUpdates

    readonly property int updatesPageIdx: PageRegistry.updatesPageIdx

    title: qsTr("Updates")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            last: !root.checkingOff
            text: qsTr("Show update indicator")
            subtext: root.checkingOff
                ? qsTr("Nothing to report while update checking is off")
                : qsTr("Always-visible icon in the taskbar that changes when a Caelestia update is available")
            checked: root.indicatorEnabled
            reset: ({
                customGet: () => root.indicatorEnabled,
                customDef: true,
                customSet: v => BarWidgets.setEnabled(GlobalConfig.bar, "updateIndicator", v)
            })
            onToggled: BarWidgets.setEnabled(GlobalConfig.bar, "updateIndicator", checked)
        }

        NavRow {
            last: true
            visible: root.checkingOff
            icon: "sync"
            label: qsTr("Turn on update checking")
            status: qsTr("Periodic checks and the indicator are off")
            onClicked: root.nState.goToSubPage(root.updatesPageIdx, PageRegistry.defaultSubPageForKey("updates"))
        }
    }
}
