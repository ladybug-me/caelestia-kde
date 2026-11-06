pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.nexus

Item {
    id: root

    property int initialPageIdx: 0
    property var initialSubPageIdx: -1
    readonly property bool windowActive: Window.window ? Window.window.active : false
    readonly property bool compact: root.width < 1120

    readonly property NexusState nState: NexusState {
        id: nState

        compact: root.compact
        pendingSubPageIdx: {
            if (root.initialSubPageIdx === -1 || root.initialSubPageIdx === undefined || root.initialSubPageIdx === "")
                return -1;
            return (typeof root.initialSubPageIdx === "number")
                ? root.initialSubPageIdx
                : PageDictionary.defaultSubPageForKey(root.initialSubPageIdx);
        }
        currentPageIdx: root.initialPageIdx

        onClose: root.requestClose()
        onCurrentPageIdxChanged: {
            if (root.navigatingFromSearch)
                return;
            root.activePane = 0;
            subcategoryPane.clearSelection();
            pages.clearSelection();
        }
        onCompactSubcategoriesChanged: {
            if (!compactSubcategories && root.compact && root.activePane === 1) {
                root.activePane = 0;
                subcategoryPane.clearSelection();
            }
        }
    }
    property color blobColour: Colours.tPalette.m3surfaceContainerLow
    property int activePane: 0
    property bool navigatingFromSearch: false
    readonly property bool hasActiveInputField: root.isInputField(Window.window ? Window.window.activeFocusItem : null)
    readonly property var targetScreen: nState.screen ?? Window.window?.screen ?? Quickshell.screens[0]

    signal close

    function requestClose(): void {
        root.close();
    }

    function isInputField(item: var): bool {
        let cur = item;
        while (cur) {
            if (cur.cursorPosition !== undefined || cur.inputMethodHints !== undefined || cur.capturedKey !== undefined)
                return true;
            cur = cur.parent ?? null;
        }
        return false;
    }

    function focusSearchBar(): void {
        if (root.compact && root.nState.compactSubcategories)
            root.nState.exitCompactPage();
        root.activePane = 0;
        subcategoryPane.clearSelection();
        pages.clearSelection();
        navPane.focusSearchBar();
    }

    function clearSearchFocus(): void {
        navPane.clearSearchFocus();
        root.forceActiveFocus();
    }

    function moveUp(): void {
        if (root.activePane === 2)
            pages.moveUp();
        else if (root.activePane === 1)
            subcategoryPane.moveUp();
        else
            navPane.moveUp();
    }

    function moveDown(): void {
        if (root.activePane === 2)
            pages.moveDown();
        else if (root.activePane === 1)
            subcategoryPane.moveDown();
        else
            navPane.moveDown();
    }

    function activateSelected(): void {
        if (root.activePane === 2) {
            pages.activateSelected();
        } else if (root.activePane === 1) {
            subcategoryPane.activateSelected();
            root.activePane = 2;
            pages.selectFirst();
        } else {
            const wasSearchOpen = root.nState.searchOpen;
            navPane.activateSelected();
            if (!wasSearchOpen) {
                if (root.compact)
                    root.nState.enterCompactPage();
                root.activePane = 1;
                subcategoryPane.selectCurrentOrFirst();
            }
        }
    }

    function goLeft(): void {
        if (root.activePane === 2) {
            if (pages.stepLeft())
                return;
            if (root.nState.subPageIdxStack.length > 0) {
                WindowFactory.goBack();
            } else {
                root.activePane = 1;
                pages.clearSelection();
                subcategoryPane.selectCurrentOrFirst();
            }
        } else if (root.activePane === 1) {
            if (root.compact)
                root.nState.exitCompactPage();
            root.activePane = 0;
            subcategoryPane.clearSelection();
            navPane.selectCurrentOrFirst();
        }
    }

    function goRight(): void {
        if (root.activePane === 2) {
            if (!pages.stepRight())
                pages.activateSelected();
        } else if (root.activePane === 1) {
            subcategoryPane.activateSelected();
            root.activePane = 2;
            pages.selectFirst();
        } else {
            const wasSearchOpen = root.nState.searchOpen;
            navPane.activateSelected();
            if (!wasSearchOpen) {
                if (root.compact)
                    root.nState.enterCompactPage();
                root.activePane = 1;
                subcategoryPane.selectCurrentOrFirst();
            }
        }
    }

    function currentFlickable(): var {
        let item = pages.currentItem;
        while (item) {
            if (item.flickable !== undefined)
                return item.flickable;
            item = item.currentItem ?? null;
        }
        return null;
    }

    function scrollCurrentPage(event: var): bool {
        if (event.x <= subcategoryPane.x + subcategoryPane.width)
            return false;

        const f = root.currentFlickable();
        if (!f || !f.interactive)
            return false;

        // The page already handles the wheel when the cursor is over it.
        const pos = f.mapFromItem(root, event.x, event.y);
        if (pos.x >= 0 && pos.y >= 0 && pos.x <= f.width && pos.y <= f.height)
            return false;

        const maxY = Math.max(0, f.contentHeight - f.height);
        if (maxY <= 0)
            return false;

        f.contentY = Math.max(0, Math.min(maxY, f.contentY - event.angleDelta.y));
        return true;
    }

    implicitHeight: (targetScreen ? targetScreen.height : 1080) * Tokens.sizes.nexus.heightMult
    implicitWidth: implicitHeight * Tokens.sizes.nexus.ratio

    Behavior on blobColour {
        CAnim {}
    }

    BlobGroup {
        id: blobGroup

        smoothing: root.Tokens.rounding.medium
        color: root.blobColour
    }

    BlobInvertedRect {
        anchors.fill: parent
        group: blobGroup
        opacity: root.blobColour.a
        radius: Tokens.rounding.large

        borderLeft: pages.x - Tokens.padding.small
        borderRight: Tokens.padding.medium
        borderTop: Tokens.padding.medium
        borderBottom: Tokens.padding.medium
    }

    NavPane {
        id: navPane

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large

        nState: nState
        width: root.compact ? Math.min(340, Math.round(root.width * 0.45)) : Math.min(285, Math.round(root.width * 0.21))
        opacity: root.compact && root.nState.compactSubcategories ? 0 : 1
        enabled: !root.compact || !root.nState.compactSubcategories

        onSearchResultSelected: (entry) => {
            root.navigatingFromSearch = true;
            root.activePane = 2;
            navPane.clearSelection();
            subcategoryPane.clearSelection();
            pages.selectEntry(entry);
            root.navigatingFromSearch = false;
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    SubcategoryPane {
        id: subcategoryPane

        anchors.left: root.compact ? parent.left : navPane.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.topMargin: navPane.anchors.margins
        anchors.bottomMargin: navPane.anchors.margins

        width: root.compact ? Math.min(340, Math.round(root.width * 0.45)) : Math.min(300, Math.round(root.width * 0.22))
        opacity: root.compact && !root.nState.compactSubcategories ? 0 : 1
        enabled: !root.compact || root.nState.compactSubcategories
        z: 1
        nState: nState

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Pages {
        id: pages

        anchors.left: subcategoryPane.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.topMargin: navPane.anchors.margins
        anchors.bottomMargin: navPane.anchors.margins
        anchors.rightMargin: navPane.anchors.margins

        nState: nState
    }

    // The page margins around the content are outside the page flickable, so
    // the wheel did nothing there. Forward it to the current page.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        onWheel: event => {
            if (root.scrollCurrentPage(event))
                event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ExtraButton1
        preventStealing: true

        onPressed: mouse => {
            WindowFactory.goBack();
            mouse.accepted = true;
        }
    }

    TapHandler {
        id: outsideTapHandler

        enabled: navPane.isSearchActive

        onPressedChanged: {
            if (pressed && !navPane.isInsideSearchRegion(root, point.position.x, point.position.y))
                root.clearSearchFocus();
        }

        onTapped: (eventPoint, button) => {
            if (!navPane.isInsideSearchRegion(root, eventPoint.position.x, eventPoint.position.y))
                root.clearSearchFocus();
        }
    }

    Shortcut {
        sequence: "/"
        enabled: root.windowActive && !root.hasActiveInputField
        autoRepeat: false

        onActivated: root.focusSearchBar()
    }

    Shortcut {
        sequences: ["Up", "k"]
        enabled: root.windowActive && !root.hasActiveInputField
        autoRepeat: true

        onActivated: root.moveUp()
    }

    Shortcut {
        sequences: ["Down", "j"]
        enabled: root.windowActive && !root.hasActiveInputField
        autoRepeat: true

        onActivated: root.moveDown()
    }

    TapHandler {
        parent: navPane

        onTapped: {
            root.activePane = 0;
            subcategoryPane.clearSelection();
            pages.clearSelection();
        }
    }

    TapHandler {
        parent: subcategoryPane

        onTapped: {
            root.activePane = 1;
            navPane.clearSelection();
            pages.clearSelection();
        }
    }

    TapHandler {
        parent: pages

        onTapped: {
            root.activePane = 2;
            navPane.clearSelection();
            subcategoryPane.clearSelection();
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.windowActive && !root.hasActiveInputField
        autoRepeat: false

        onActivated: {
            if (pages.handleEscape())
                return;
            if (root.nState.subPageIdxStack.length > 0) {
                WindowFactory.goBack();
            } else if (root.activePane === 2) {
                root.activePane = 1;
                pages.clearSelection();
                subcategoryPane.selectCurrentOrFirst();
            } else if (root.activePane === 1) {
                if (root.compact)
                    root.nState.exitCompactPage();
                root.activePane = 0;
                subcategoryPane.clearSelection();
                navPane.selectCurrentOrFirst();
            } else {
                root.requestClose();
            }
        }
    }

    Shortcut {
        sequence: "Backspace"
        enabled: root.windowActive && !root.hasActiveInputField && (root.nState.subPageIdxStack.length > 0 || root.activePane > 0)
        autoRepeat: false

        onActivated: {
            if (pages.handleEscape())
                return;
            if (root.nState.subPageIdxStack.length > 0) {
                WindowFactory.goBack();
            } else if (root.activePane === 2) {
                root.activePane = 1;
                pages.clearSelection();
                subcategoryPane.selectCurrentOrFirst();
            } else if (root.activePane === 1) {
                if (root.compact)
                    root.nState.exitCompactPage();
                root.activePane = 0;
                subcategoryPane.clearSelection();
                navPane.selectCurrentOrFirst();
            }
        }
    }

    Shortcut {
        sequence: "Delete"
        enabled: root.windowActive && !root.hasActiveInputField && root.activePane === 2
        autoRepeat: false

        onActivated: {
            if (pages.handleDelete())
                return;
        }
    }

    Shortcut {
        sequences: ["Left", "h"]
        enabled: root.windowActive && !root.hasActiveInputField
        autoRepeat: true

        onActivated: root.goLeft()
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: root.windowActive && !root.hasActiveInputField
        autoRepeat: false

        onActivated: root.activateSelected()
    }

    Shortcut {
        sequences: ["Right", "l"]
        enabled: root.windowActive && !root.hasActiveInputField
        autoRepeat: true

        onActivated: root.goRight()
    }
}
