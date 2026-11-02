import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ConnectedRect {
    id: root

    property alias label: label.text
    property string subtext
    property alias menuItems: splitButton.menuItems
    property alias active: splitButton.active
    property alias fallbackText: splitButton.fallbackText
    property alias fallbackIcon: splitButton.fallbackIcon
    property alias menuOnTop: splitButton.menuOnTop
    readonly property alias splitButton: splitButton
    readonly property alias menu: splitButton.menu
    property alias expanded: splitButton.expanded
    property var _savedActive: null

    signal selected(item: MenuItem)

    function findActiveIndex(): int {
        const items = (menuItems ?? []).filter(i => i && i.visible);
        if (items.length === 0)
            return -1;
        const idx = items.indexOf(active);
        if (idx >= 0)
            return idx;
        if (active && active.value !== undefined) {
            for (let i = 0; i < items.length; i++) {
                if (items[i].value === active.value)
                    return i;
            }
        }
        return 0;
    }

    function cycleNext(): void {
        const items = (menuItems ?? []).filter(i => i && i.visible);
        if (items.length === 0)
            return;
        const curIdx = findActiveIndex();
        const nextIdx = curIdx < 0 ? 0 : (curIdx + 1) % items.length;
        const item = items[nextIdx];
        active = item;
        item?.clicked();
        root.selected(item);
    }

    function cyclePrev(): void {
        const items = (menuItems ?? []).filter(i => i && i.visible);
        if (items.length === 0)
            return;
        const curIdx = findActiveIndex();
        const prevIdx = curIdx <= 0 ? items.length - 1 : curIdx - 1;
        const item = items[prevIdx];
        active = item;
        item?.clicked();
        root.selected(item);
    }

    function openMenu(): void {
        _savedActive = active;
        splitButton.expanded = true;
    }

    function closeMenu(revert: bool): void {
        if (!splitButton.expanded)
            return;
        if (revert && _savedActive) {
            active = _savedActive;
            active?.clicked();
            root.selected(active);
        }
        splitButton.expanded = false;
        _savedActive = null;
    }

    function stepLeft(): void {
        cyclePrev();
    }

    function stepRight(): void {
        cycleNext();
    }

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins * 2
    clip: false
    z: splitButton.expanded ? 1 : 0

    RowLayout {
        id: rowLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: label

                Layout.fillWidth: true
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtext
                text: root.subtext
                color: Colours.palette.m3onSurfaceVariant
                font: NexusStyle.secondaryFont
                elide: Text.ElideRight
            }
        }

        SplitButton {
            id: splitButton

            type: SplitButton.Tonal
            stateLayer.onClicked: splitButton.expanded = !splitButton.expanded
            menu.onItemSelected: item => root.selected(item)
        }
    }
}
