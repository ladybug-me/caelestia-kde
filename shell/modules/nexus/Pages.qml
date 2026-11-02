import QtQuick
import Caelestia.Config
import qs.components
import qs.modules.nexus

Item {
    id: root

    required property NexusState nState

    property int lastPageIdx
    property int animOff
    readonly property int animMovement: Tokens.padding.extraExtraLarge * 2
    property Item currentItem
    property int loadGeneration: 0
    property var pendingEntry: null

    function loadPage(idx: int): void {
        const generation = ++loadGeneration;

        if (currentItem) {
            currentItem.visible = false;
            currentItem.destroy();
            currentItem = null;
        }

        const comp = PageCompRegistry.pageComps[idx] ?? PageCompRegistry.placeholderComp;
        const incubator = comp.incubateObject(container, {
            nState,
            visible: false
        });

        const attach = () => {
            if (generation !== loadGeneration) {
                incubator.object.destroy();
                return;
            }

            incubator.object.anchors.fill = container;
            incubator.object.visible = true;
            currentItem = incubator.object;
            if (root.pendingEntry) {
                root.selectEntry(root.pendingEntry);
            }
        };

        if (incubator.status === Component.Ready)
            attach();
        else
            incubator.onStatusChanged = status => {
                if (status === Component.Ready)
                    attach();
                else if (status === Component.Error && incubator.object)
                    incubator.object.destroy();
            };
    }

    function activePage(): var {
        let item = root.currentItem;
        while (item) {
            if (item.contentChild !== undefined && item.flickable !== undefined)
                return item;
            item = item.currentItem ?? null;
        }
        return null;
    }

    function moveUp(): void {
        const page = activePage();
        if (page && typeof page.moveUp === "function")
            page.moveUp();
    }

    function moveDown(): void {
        const page = activePage();
        if (page && typeof page.moveDown === "function")
            page.moveDown();
    }

    function selectFirst(): void {
        const page = activePage();
        if (page && typeof page.selectFirst === "function")
            page.selectFirst();
    }

    function activateSelected(): void {
        const page = activePage();
        if (page && typeof page.activateSelected === "function")
            page.activateSelected();
    }

    function clearSelection(): void {
        root.pendingEntry = null;
        const page = activePage();
        if (page && typeof page.clearSelection === "function")
            page.clearSelection();
    }

    function selectEntry(entry: var): void {
        root.pendingEntry = entry;
        const page = activePage();
        if (page && typeof page.selectItemByLabel === "function") {
            const label = entry?.settingLabel || entry?.pageLabel || "";
            page.selectItemByLabel(label);
            root.pendingEntry = null;
        } else if (page && typeof page.selectFirst === "function") {
            page.selectFirst();
            root.pendingEntry = null;
        }
    }

    function stepLeft(): bool {
        const page = activePage();
        if (page && typeof page.stepLeft === "function")
            return page.stepLeft();
        return false;
    }

    function stepRight(): bool {
        const page = activePage();
        if (page && typeof page.stepRight === "function")
            return page.stepRight();
        return false;
    }

    function handleEscape(): bool {
        const page = activePage();
        if (page && typeof page.handleEscape === "function")
            return page.handleEscape();
        return false;
    }

    function handleDelete(): bool {
        const page = activePage();
        if (page && typeof page.handleDelete === "function")
            return page.handleDelete();
        return false;
    }

    Item {
        id: container

        objectName: "PageContainer"
        anchors.fill: parent
        layer.enabled: opacity < 1
        Component.onCompleted: root.loadPage(root.nState.currentPageIdx)
    }

    Connections {
        function onCurrentPageIdxChanged(): void {
            root.clearSelection();
            switchAnim.complete();
            root.animOff = root.animMovement * (root.nState.currentPageIdx > root.lastPageIdx ? 1 : -1);
            switchAnim.start();
            root.lastPageIdx = root.nState.currentPageIdx;
        }

        target: root.nState
    }

    SequentialAnimation {
        id: switchAnim

        Anim {
            target: container
            property: "opacity"
            to: 0
            type: Anim.DefaultEffects
        }
        ScriptAction {
            script: root.loadPage(root.nState.currentPageIdx)
        }
        PropertyAction {
            target: container.anchors
            property: "topMargin"
            value: root.animOff
        }
        PropertyAction {
            target: container.anchors
            property: "bottomMargin"
            value: -root.animOff
        }
        ParallelAnimation {
            Anim {
                target: container
                property: "opacity"
                from: 0
                to: 1
                type: Anim.SlowEffects
            }
            Anim {
                target: container.anchors
                properties: "topMargin,bottomMargin"
                to: 0
                type: Anim.SlowEffects
            }
        }
    }
}
