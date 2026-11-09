pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property int panelCount: GlobalConfig.bar.panels.count
    readonly property bool hasPanel: root.selectedIndex >= 0 && root.selectedIndex < root.panelCount
    readonly property var selectedPanel: root.hasPanel ? GlobalConfig.bar.panels.at(root.selectedIndex) : null
    readonly property var barRows: BarPanels.rows
    readonly property var alignItems: root.itemsOf(alignInstantiator)
    readonly property var positionItems: root.itemsOf(edgeInstantiator)
    readonly property var screenItems: root.itemsOf(screenInstantiator)
    readonly property var addableEdges: root.freeEdges("").map(edge => ({
        id: edge,
        label: root.edgeLabel(edge)
    }))
    readonly property var screenModel: [{
        name: "",
        label: qsTr("All screens")
    }].concat(Quickshell.screens.map(s => ({
        name: s.name,
        label: s.name
    })))

    property int selectedIndex: -1
    property real lengthDraft: -1

    readonly property Timer lengthTimer: Timer {
        interval: 250

        onTriggered: {
            if (root.lengthDraft >= 0 && root.selectedPanel)
                root.selectedPanel.lengthPercent = Math.round(root.lengthDraft);

            root.lengthDraft = -1;
        }
    }
    readonly property Instantiator alignInstantiator: Instantiator {
        model: ["start", "center", "end"]

        delegate: MenuItem {
            required property string modelData

            value: modelData
            text: root.alignLabel(modelData)
        }
    }
    readonly property Instantiator edgeInstantiator: Instantiator {
        model: root.freeEdges(root.selectedPanel?.position ?? "")

        delegate: MenuItem {
            required property string modelData

            value: modelData
            text: root.edgeLabel(modelData)
        }
    }
    readonly property Instantiator screenInstantiator: Instantiator {
        model: root.screenModel

        delegate: MenuItem {
            required property var modelData

            value: modelData.name
            text: modelData.label
        }
    }

    function itemsOf(instantiator: Instantiator): var {
        const items = [];

        for (let i = 0; i < instantiator.count; ++i)
            items.push(instantiator.objectAt(i));

        return items;
    }
    function itemFor(items: var, value: string): MenuItem {
        for (let i = 0; i < items.length; ++i)
            if (items[i].value === value)
                return items[i];

        return items.length > 0 ? items[0] : null;
    }
    function alignLabel(align: string): string {
        return BarPanels.alignLabel(align);
    }
    function edgeLabel(edge: string): string {
        return BarPanels.edgeLabel(edge);
    }
    function edgesInUse(): var {
        return BarPanels.edgesInUse();
    }
    function freeEdges(keep: string): var {
        return BarPanels.freeEdges(keep);
    }
    function addBar(position: string): void {
        BarPanels.addPanel(position);
        root.selectedIndex = root.panelCount - 1;
    }
    function removeSelected(): void {
        const index = root.selectedIndex;
        if (index < 0 || index >= root.panelCount)
            return;

        BarPanels.removePanel(index);
        root.selectedIndex = Math.min(index, root.panelCount - 1);
    }
    function queueLength(value: real): void {
        root.lengthDraft = value;
        root.lengthTimer.restart();
    }

    title: qsTr("Extra bars")
    isSubPage: true

    onSelectedIndexChanged: root.lengthDraft = -1

    Component.onCompleted: {
        if (root.nState && root.nState.extraBarsTarget >= 0) {
            root.selectedIndex = root.nState.extraBarsTarget;
            root.nState.extraBarsTarget = -1;
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Bars")
        }

        Repeater {
            model: root.barRows

            RowButton {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === root.barRows.length - 1
                icon: root.selectedIndex === modelData.index ? "radio_button_checked" : "radio_button_unchecked"
                text: modelData.name
                subtext: root.edgeLabel(modelData.edge) + " · " + (modelData.screens.length > 0 ? modelData.screens[0] : qsTr("All screens"))
                onClicked: root.selectedIndex = modelData.index
            }
        }

        DialogSelectButton {
            rootParent: root.flickable

            visible: root.addableEdges.length > 0
            icon: "add"
            label: qsTr("Add bar")
            header: qsTr("Which edge?")
            acceptLabel: qsTr("Add")
            model: root.addableEdges
            onAccepted: {
                if (selectedItem)
                    root.addBar(selectedItem);
            }
        }

        RowButton {
            Layout.fillWidth: true

            visible: root.addableEdges.length === 0
            first: GlobalConfig.bar.panels.count === 0
            last: true
            icon: "info"
            text: qsTr("Every edge has a bar")
            subtext: qsTr("Move or remove one to free an edge")
        }

        SectionHeader {
            visible: root.hasPanel
            text: root.selectedPanel ? (root.selectedPanel.name || qsTr("Unnamed bar")) : ""
        }

        TextFieldRow {
            Layout.fillWidth: true

            visible: root.hasPanel
            first: true
            label: qsTr("Name")
            placeholderText: qsTr("Bar %1").arg(root.selectedIndex + 2)
            maximumLength: 40
            value: root.selectedPanel?.name ?? ""
            onEditingFinished: value => {
                if (root.selectedPanel)
                    root.selectedPanel.name = value;
            }
        }

        SelectRow {
            Layout.fillWidth: true

            visible: root.hasPanel
            label: qsTr("Position")
            subtext: qsTr("Only the edges without a bar are offered")
            menuItems: root.positionItems
            active: root.itemFor(root.positionItems, root.selectedPanel?.position ?? "")
            onSelected: item => {
                if (root.selectedPanel)
                    root.selectedPanel.position = item.value;
            }
        }

        SelectRow {
            Layout.fillWidth: true

            visible: root.hasPanel
            label: qsTr("Alignment")
            menuItems: root.alignItems
            active: root.itemFor(root.alignItems, root.selectedPanel?.align ?? "center")
            onSelected: item => {
                if (root.selectedPanel)
                    root.selectedPanel.align = item.value;
            }
        }

        StepperRow {
            Layout.fillWidth: true

            visible: root.hasPanel
            label: qsTr("Length")
            subtext: qsTr("Share of the edge the bar takes")
            from: 10
            to: 100
            stepSize: 5
            value: root.lengthDraft >= 0 ? root.lengthDraft : (root.selectedPanel?.lengthPercent ?? 100)
            onMoved: value => root.queueLength(value)
        }

        SelectRow {
            Layout.fillWidth: true

            visible: root.hasPanel
            label: qsTr("Screens")
            menuItems: root.screenItems
            active: root.itemFor(root.screenItems, root.selectedPanel && root.selectedPanel.screens.length > 0 ? root.selectedPanel.screens[0] : "")
            onSelected: item => {
                if (root.selectedPanel)
                    root.selectedPanel.screens = item.value ? [item.value] : [];
            }
        }

        ToggleRow {
            Layout.fillWidth: true

            visible: root.hasPanel
            text: qsTr("Enabled")
            checked: root.selectedPanel?.enabled ?? true
            onToggled: {
                if (root.selectedPanel)
                    root.selectedPanel.enabled = checked;
            }
        }

        ToggleRow {
            Layout.fillWidth: true

            visible: root.hasPanel
            text: qsTr("Always visible")
            subtext: qsTr("Keep the bar on screen instead of revealing it on hover")
            checked: root.selectedPanel?.persistent ?? true
            onToggled: {
                if (root.selectedPanel)
                    root.selectedPanel.persistent = checked;
            }
        }

        ToggleRow {
            Layout.fillWidth: true

            visible: root.hasPanel
            enabled: !(root.selectedPanel?.persistent ?? true)
            text: qsTr("Show on hover")
            checked: root.selectedPanel?.showOnHover ?? true
            onToggled: {
                if (root.selectedPanel)
                    root.selectedPanel.showOnHover = checked;
            }
        }

        RowButton {
            Layout.fillWidth: true

            icon: "widgets"
            text: qsTr("Widgets of this bar")
            subtext: qsTr("Pick the components it shows")
            onClicked: {
                root.nState.barComponentsTarget = root.selectedIndex;
                root.nState.openSubPage("barComponents");
            }
        }

        RowButton {
            Layout.fillWidth: true

            visible: root.hasPanel
            last: true
            icon: "delete"
            text: qsTr("Remove this bar")
            onClicked: root.removeSelected()
        }
    }
}
