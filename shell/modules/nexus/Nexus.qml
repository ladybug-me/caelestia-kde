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
    property string initialSubPage: ""
    readonly property bool windowActive: Window.window ? Window.window.active : false
    readonly property bool sidePane: GlobalConfig.nexus.sidePane

    // The fold is what the three-pane layout does when it runs out of width,
    // so it is meaningless without the pane that gets folded away.
    readonly property bool compact: root.width < 1120 && root.sidePane

    readonly property NexusState nState: NexusState {
        id: nState

        compact: root.compact
        sidePane: root.sidePane
        pendingSubPageKey: root.initialSubPage || ""
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

    function navPaneWidth(): int {
        if (root.compact)
            return Math.min(340, Math.round(root.width * 0.45));
        // Without the side pane the list carries the width it had before the
        // three-pane layout took a slice of it.
        if (!root.sidePane)
            return Math.min(Tokens.sizes.nexus.maxNavWidth, Math.round(root.width / 3));
        return Math.min(285, Math.round(root.width * 0.21));
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

    // Pane 1 is the subcategory pane. Without it the section list and the
    // content are neighbours, so stepping in skips the middle pane and
    // stepping out lands on the sections.
    function enterSubcategories(): void {
        if (root.sidePane) {
            root.activePane = 1;
            subcategoryPane.selectCurrentOrFirst();
        } else {
            root.activePane = 2;
            pages.selectFirst();
        }
    }

    function leaveSubcategories(): void {
        if (root.compact)
            root.nState.exitCompactPage();
        subcategoryPane.clearSelection();
        root.activePane = 0;
        navPane.selectCurrentOrFirst();
    }

    function leaveContent(): void {
        pages.clearSelection();
        if (root.sidePane) {
            root.activePane = 1;
            subcategoryPane.selectCurrentOrFirst();
        } else {
            root.activePane = 0;
            navPane.selectCurrentOrFirst();
        }
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
                root.enterSubcategories();
            }
        }
    }

    function goLeft(): void {
        if (root.activePane === 2) {
            if (pages.stepLeft())
                return;
            if (root.nState.subPageKeyStack.length > 0) {
                WindowFactory.goBack();
            } else {
                root.leaveContent();
            }
        } else if (root.activePane === 1) {
            root.leaveSubcategories();
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
                root.enterSubcategories();
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
        if (event.x <= (root.sidePane ? subcategoryPane.x + subcategoryPane.width : navPane.x + navPane.width))
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
        width: root.navPaneWidth()
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

        visible: root.sidePane
        anchors.left: root.compact ? parent.left : navPane.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.topMargin: navPane.anchors.margins
        anchors.bottomMargin: navPane.anchors.margins

        width: root.compact ? Math.min(340, Math.round(root.width * 0.45)) : Math.min(300, Math.round(root.width * 0.22))
        opacity: root.compact && !root.nState.compactSubcategories ? 0 : 1
        enabled: root.sidePane && (!root.compact || root.nState.compactSubcategories)
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

        anchors.left: root.sidePane ? subcategoryPane.right : navPane.right
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
            if (root.nState.subPageKeyStack.length > 0) {
                WindowFactory.goBack();
            } else if (root.activePane === 2) {
                root.leaveContent();
            } else if (root.activePane === 1) {
                root.leaveSubcategories();
            } else {
                root.requestClose();
            }
        }
    }

    Shortcut {
        sequence: "Backspace"
        enabled: root.windowActive && !root.hasActiveInputField && (root.nState.subPageKeyStack.length > 0 || root.activePane > 0)
        autoRepeat: false

        onActivated: {
            if (pages.handleEscape())
                return;
            if (root.nState.subPageKeyStack.length > 0) {
                WindowFactory.goBack();
            } else if (root.activePane === 2) {
                root.leaveContent();
            } else if (root.activePane === 1) {
                root.leaveSubcategories();
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
