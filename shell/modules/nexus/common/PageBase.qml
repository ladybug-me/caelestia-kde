pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.nexus

ColumnLayout {
    id: root

    readonly property bool isPageBase: true
    required property string title
    required property NexusState nState
    property bool isSubPage
    property bool scrollable: true
    property bool showTitle: true
    readonly property int cappedWidth: Math.min(Tokens.sizes.nexus.maxContentWidth, width)
    readonly property alias flickable: flickable
    property list<Item> headerActions

    default property Item contentChild
    property int selectedIndex: -1
    property bool selectionActive: false
    property Item selectedItem: null

    function getNavigableItems(): var {
        const items = [];
        collectItems(root.contentChild, items);
        items.sort((a, b) => {
            try {
                const ptA = a.mapToItem(flickable.contentItem, 0, 0);
                const ptB = b.mapToItem(flickable.contentItem, 0, 0);
                if (Math.abs(ptA.y - ptB.y) > 4)
                    return ptA.y - ptB.y;
                return ptA.x - ptB.x;
            } catch (e) {
                return 0;
            }
        });
        return items;
    }

    function collectItems(item: var, list: var): void {
        if (!item || !item.visible || item.opacity === 0 || item.enabled === false)
            return;

        if (item.contentItem !== undefined && item.interactive !== undefined && item !== flickable) {
            const content = item.contentItem;
            if (content && content.children) {
                for (let i = 0; i < content.children.length; i++)
                    collectItems(content.children[i], list);
            }
            return;
        }

        const isRow = (typeof item.clicked === "function" && item.parent !== null) ||
                      (typeof item.toggle === "function") ||
                      (typeof item.toggled === "function") ||
                      (item.first !== undefined && item.last !== undefined) ||
                      (item.spacious !== undefined) ||
                      (item.menuItems !== undefined) ||
                      (item.field !== undefined && item.smallField !== undefined) ||
                      (item.popup !== undefined && item.keepPopupAsChild !== undefined) ||
                      (item.isExpanded !== undefined && item.titleText !== undefined) ||
                      (item.value !== undefined && (item.stepSize !== undefined || item.reset !== undefined || item.moved !== undefined));

        const isContainer = item.children && item.children.length > 0 &&
                            (item.toString().indexOf("QQuickColumnLayout") >= 0 ||
                             item.toString().indexOf("QQuickRowLayout") >= 0 ||
                             item.toString().indexOf("QQuickColumn") >= 0 ||
                             item.toString().indexOf("QQuickRow") >= 0);

        const isSectionHeader = item.font !== undefined && item.text !== undefined &&
                                typeof item.clicked !== "function" && typeof item.toggle !== "function";

        if (isRow && !isContainer && !isSectionHeader) {
            list.push(item);
            return;
        }

        if (item.item !== undefined && item.item)
            collectItems(item.item, list);

        if (item.children) {
            for (let i = 0; i < item.children.length; i++)
                collectItems(item.children[i], list);
        }
    }

    function setItemSelection(item: var, selected: bool): void {
        if (!item)
            return;
        if (item.isSelected !== undefined)
            item.isSelected = selected;
        else if (item.bg && item.bg.isSelected !== undefined)
            item.bg.isSelected = selected;
        else if (item.background && item.background.isSelected !== undefined)
            item.background.isSelected = selected;
    }

    function moveUp(): void {
        if (root.selectionActive && root.selectedItem?.splitButton?.expanded) {
            if (typeof root.selectedItem.cyclePrev === "function") {
                root.selectedItem.cyclePrev();
                return;
            }
        }
        const items = getNavigableItems();
        if (items.length === 0)
            return;
        setItemSelection(root.selectedItem, false);
        root.selectionActive = true;
        if (root.selectedIndex <= 0 || root.selectedIndex >= items.length)
            root.selectedIndex = items.length - 1;
        else
            root.selectedIndex = root.selectedIndex - 1;
        root.selectedItem = items[root.selectedIndex];
        setItemSelection(root.selectedItem, true);
        ensureVisible(root.selectedItem);
    }

    function moveDown(): void {
        if (root.selectionActive && root.selectedItem?.splitButton?.expanded) {
            if (typeof root.selectedItem.cycleNext === "function") {
                root.selectedItem.cycleNext();
                return;
            }
        }
        const items = getNavigableItems();
        if (items.length === 0)
            return;
        setItemSelection(root.selectedItem, false);
        root.selectionActive = true;
        if (root.selectedIndex < 0 || root.selectedIndex >= items.length - 1)
            root.selectedIndex = 0;
        else
            root.selectedIndex = root.selectedIndex + 1;
        root.selectedItem = items[root.selectedIndex];
        setItemSelection(root.selectedItem, true);
        ensureVisible(root.selectedItem);
    }

    function selectFirst(): void {
        const items = getNavigableItems();
        if (items.length === 0)
            return;
        setItemSelection(root.selectedItem, false);
        root.selectionActive = true;
        root.selectedIndex = 0;
        root.selectedItem = items[0];
        setItemSelection(root.selectedItem, true);
        ensureVisible(root.selectedItem);
    }

    function selectItemByLabel(labelStr: string, retryCount = 0): bool {
        const items = getNavigableItems();
        if (items.length === 0) {
            if (retryCount < 5) {
                Qt.callLater(() => {
                    root.selectItemByLabel(labelStr, retryCount + 1);
                });
            }
            return false;
        }
        if (!labelStr) {
            selectFirst();
            return true;
        }
        const target = labelStr.trim().toLowerCase();
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            const itemLabel = String(item.label?.text || item.label || item.titleText || item.text || item.actionName || "").trim().toLowerCase();
            if (itemLabel === target || (itemLabel && target && (itemLabel.indexOf(target) >= 0 || target.indexOf(itemLabel) >= 0))) {
                setItemSelection(root.selectedItem, false);
                root.selectionActive = true;
                root.selectedIndex = i;
                root.selectedItem = item;
                setItemSelection(root.selectedItem, true);
                ensureVisible(root.selectedItem);
                return true;
            }
        }
        selectFirst();
        return true;
    }

    function stepLeft(): bool {
        if (!root.selectionActive || !root.selectedItem)
            return false;
        if (root.selectedItem?.splitButton?.expanded) {
            if (typeof root.selectedItem.closeMenu === "function")
                root.selectedItem.closeMenu(true);
            else if (root.selectedItem.splitButton)
                root.selectedItem.splitButton.expanded = false;
            return true;
        }
        const item = root.selectedItem;
        if (typeof item.stepLeft === "function") {
            const res = item.stepLeft();
            return res !== undefined ? Boolean(res) : true;
        }
        return false;
    }

    function stepRight(): bool {
        if (!root.selectionActive || !root.selectedItem)
            return false;
        if (root.selectedItem?.splitButton?.expanded) {
            if (typeof root.selectedItem.closeMenu === "function")
                root.selectedItem.closeMenu(false);
            else if (root.selectedItem.splitButton)
                root.selectedItem.splitButton.expanded = false;
            return true;
        }
        const item = root.selectedItem;
        if (typeof item.stepRight === "function") {
            const res = item.stepRight();
            return res !== undefined ? Boolean(res) : true;
        }
        return false;
    }

    function handleEscape(): bool {
        if (root.selectedItem?.splitButton?.expanded) {
            if (typeof root.selectedItem.closeMenu === "function")
                root.selectedItem.closeMenu(true);
            else
                root.selectedItem.splitButton.expanded = false;
            return true;
        }
        if (root.selectedItem?.popup?.open) {
            root.selectedItem.popup.open = false;
            return true;
        }
        if (root.selectedItem?.open && root.selectedItem?.rootParent) {
            root.selectedItem.open = false;
            return true;
        }
        if (typeof root.selectedItem?.handleEscape === "function" && root.selectedItem.handleEscape())
            return true;
        return false;
    }

    function handleDelete(): bool {
        if (!root.selectionActive || !root.selectedItem)
            return false;
        const item = root.selectedItem;
        if (typeof item.handleDelete === "function")
            return Boolean(item.handleDelete());
        return false;
    }

    function activateSelected(): void {
        if (!root.selectionActive || !root.selectedItem)
            return;
        const item = root.selectedItem;
        if (item.splitButton !== undefined) {
            if (item.splitButton.expanded) {
                if (typeof item.closeMenu === "function")
                    item.closeMenu(false);
                else
                    item.splitButton.expanded = false;
            } else {
                if (typeof item.openMenu === "function")
                    item.openMenu();
                else
                    item.splitButton.expanded = true;
            }
        } else if (item.field !== undefined && typeof item.field.forceActiveFocus === "function") {
            item.field.forceActiveFocus();
            if (typeof item.field.selectAll === "function")
                item.field.selectAll();
        } else if (item.popup !== undefined) {
            item.popup.open = !item.popup.open;
        } else if (item.isExpanded !== undefined) {
            item.isExpanded = !item.isExpanded;
        } else if (typeof item.toggle === "function") {
            item.toggle();
        } else if (typeof item.clicked === "function") {
            item.clicked();
        } else if (typeof item.toggled === "function") {
            if (item.checked !== undefined)
                item.checked = !item.checked;
            item.toggled();
        } else if (item.iconClickable && typeof item.iconClicked === "function") {
            item.iconClicked();
        } else if (item.children) {
            for (let i = 0; i < item.children.length; i++) {
                const child = item.children[i];
                if (child && typeof child.clicked === "function" && child.enabled) {
                    child.clicked(null);
                    return;
                }
            }
        }
    }

    function clearSelection(): void {
        setItemSelection(root.selectedItem, false);
        root.selectionActive = false;
        root.selectedIndex = -1;
        root.selectedItem = null;
    }

    function ensureVisible(item: Item): void {
        if (!item)
            return;
        try {
            const pt = item.mapToItem(flickable.contentItem, 0, 0);
            const top = pt.y;
            const bottom = pt.y + item.height;
            if (top < flickable.contentY) {
                flickable.contentY = Math.max(0, top - Tokens.padding.medium);
            } else if (bottom > flickable.contentY + flickable.height) {
                flickable.contentY = bottom - flickable.height + Tokens.padding.medium;
            }
        } catch (e) {}
    }

    spacing: root.showTitle ? Tokens.spacing.extraSmall : Tokens.spacing.medium

    Item {
        id: headerBand

        z: 1
        visible: true
        implicitWidth: header.implicitWidth
        implicitHeight: 46
        Layout.preferredHeight: 46
        Layout.fillWidth: true

        RowLayout {
            id: header

            anchors.fill: parent
            spacing: Tokens.spacing.largeIncreased

            Loader {
                visible: active
                active: root.isSubPage && root.nState.subPageIdxStack.length > 0
                asynchronous: true
                sourceComponent: IconButton {
                    icon: "arrow_back"
                    font: Tokens.font.icon.medium
                    type: IconButton.Tonal
                    isRound: true
                    inactiveColour: Colours.tPalette.m3surfaceContainerHigh
                    inactiveOnColour: Colours.palette.m3onSurfaceVariant
                    onClicked: root.nState.closeSubPage()
                }
            }

            StyledText {
                visible: root.showTitle && root.title.length > 0
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.title
                font: Tokens.font.title.large
                elide: Text.ElideRight
            }

            Item {
                visible: !root.showTitle || root.title.length === 0
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacing.small
                children: root.headerActions
            }
        }
    }

    VerticalFadeFlickable {
        id: flickable

        interactive: root.scrollable
        Layout.fillWidth: true
        Layout.fillHeight: true

        topMargin: 0
        bottomMargin: Tokens.padding.large

        contentHeight: root.scrollable ? (root.contentChild?.implicitHeight ?? 0) : height
        contentItem.children: [root.contentChild]
    }

    TapHandler {
        onTapped: root.clearSelection()
    }
}
