pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common
import qs.modules.nexus.pages.panels.taskbar

BarComponents {
    id: root

    property var panelIndex: root.nState.editingPanelIndex
    readonly property var panel: (panelIndex >= 0 && panelIndex < GlobalConfig.bar.bars.values.length) ? GlobalConfig.bar.bars.values[panelIndex] : null

    title: qsTr("Activar y reorganizar")
    isSubPage: true
    nState: root.nState
    entriesOverride: root.panel ? root.panel.entries : null
    writeEntries: entries => {
        if (root.panel)
            root.panel.entries = entries;
    }
}
