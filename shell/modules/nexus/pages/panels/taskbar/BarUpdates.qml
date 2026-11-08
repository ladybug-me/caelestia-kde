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

    readonly property int updatesPageIdx: {
        const idx = PageRegistry.indexForKey("updates");
        return idx >= 0 ? idx : 0;
    }

    title: qsTr("Updates")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            last: GlobalConfig.general.checkUpdates
            text: qsTr("Show update indicator")
            subtext: GlobalConfig.general.checkUpdates
                ? qsTr("Always-visible icon in the taskbar that changes when a Caelestia update is available")
                : qsTr("Nothing to report while update checking is off")
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
            visible: !GlobalConfig.general.checkUpdates
            icon: "sync"
            label: qsTr("Turn on update checking")
            status: qsTr("Periodic checks and the indicator are off")
            onClicked: root.nState.goToPage(root.updatesPageIdx)
        }
    }
}
