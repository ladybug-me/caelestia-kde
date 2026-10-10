pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property int panelIndex: root.nState.editingPanelIndex
    readonly property var panel: (panelIndex >= 0 && panelIndex < GlobalConfig.bar.bars.values.length) ? GlobalConfig.bar.bars.values[panelIndex] : null

    readonly property var positionItems: [
        { value: "top", text: qsTr("Top") },
        { value: "bottom", text: qsTr("Bottom") },
        { value: "left", text: qsTr("Left") },
        { value: "right", text: qsTr("Right") }
    ]
    readonly property var freePositions: {
        const taken = [];
        if (GlobalConfig.bar.position)
            taken.push(GlobalConfig.bar.position);
        const bars = GlobalConfig.bar.bars.values;
        for (let i = 0; i < bars.length; i++) {
            if (i !== root.panelIndex && bars[i] && bars[i].enabled !== false)
                taken.push(bars[i].position || "bottom");
        }
        return root.positionItems.filter(item => !taken.includes(item.value));
    }

    function positionText(value: string): string {
        for (let i = 0; i < root.positionItems.length; i++) {
            if (root.positionItems[i].value === value)
                return root.positionItems[i].text;
        }
        return value;
    }

    title: root.panel ? (root.panel.name || qsTr("Panel")) : qsTr("Panel")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Panel")
        }

        TextFieldRow {
            first: true
            label: qsTr("Name")
            value: root.panel ? root.panel.name : ""
            onEditingFinished: value => {
                if (root.panel)
                    root.panel.name = value;
            }
        }

        DialogSelectButton {
            rootParent: root.flickable
            icon: "dock_to_bottom"
            label: root.panel ? root.positionText(root.panel.position || "bottom") : ""
            header: qsTr("Panel position")
            acceptLabel: qsTr("Move")
            model: root.freePositions.map(item => ({
                        id: item.value,
                        label: item.text
                    }))
            enabled: root.panel !== null && root.freePositions.length > 0
            onAccepted: {
                if (selectedItem && root.panel)
                    root.panel.position = selectedItem;
            }
        }

        ToggleRow {
            text: qsTr("Persistent")
            subtext: qsTr("Keep the panel visible at all times")
            checked: root.panel ? (root.panel.persistent ?? true) : true
            onToggled: {
                if (root.panel)
                    root.panel.persistent = checked;
            }
        }

        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal the panel when the pointer touches the edge")
            checked: root.panel ? (root.panel.showOnHover ?? true) : true
            onToggled: {
                if (root.panel)
                    root.panel.showOnHover = checked;
            }
        }

        StepperRow {
            last: true
            label: qsTr("Length")
            subtext: qsTr("Panel width in percent; below 100 it floats as a dock")
            value: root.panel ? (root.panel.lengthPercent ?? 100) : 100
            from: 10
            to: 100
            stepSize: 5
            onMoved: v => {
                if (root.panel)
                    root.panel.lengthPercent = Math.round(v);
            }
        }

        BarComponents {
            isSubPage: false
            title: qsTr("Components")
            nState: root.nState
            Layout.fillWidth: true
            Layout.preferredHeight: 520
            entriesOverride: root.panel ? root.panel.entries : null
            writeEntries: entries => {
                if (root.panel)
                    root.panel.entries = entries;
            }
        }
    }
}
