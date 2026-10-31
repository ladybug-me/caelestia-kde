import "navpane"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus

ColumnLayout {
    id: root

    required property NexusState nState
    readonly property bool isSearchActive: searchField.activeFocus

    signal searchResultSelected(var entry)

    // Rapid keystrokes are batched with a brief debounce before publishing.
    function publishQuery(): void {
        searchDebounce.stop();
        root.nState.searchQuery = searchField.text;
    }

    function clearQuery(): void {
        searchDebounce.stop();
        root.nState.searchQuery = "";
    }

    function focusSearchBar(): void {
        if (root.nState.compact && root.nState.compactSubcategories)
            root.nState.exitCompactPage();
        navLocations.selectionActive = false;
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    function clearSearchFocus(): void {
        searchField.focus = false;
        root.forceActiveFocus();
    }

    function moveUp(): void {
        if (root.nState.searchOpen)
            searchResults.moveUp();
        else
            navLocations.moveUp();
    }

    function moveDown(): void {
        if (root.nState.searchOpen)
            searchResults.moveDown();
        else
            navLocations.moveDown();
    }

    function activateSelected(): void {
        if (root.nState.searchOpen)
            searchResults.executeSelected();
        else
            navLocations.activateSelected();
    }

    function clearSelection(): void {
        navLocations.clearSelection();
    }

    function selectCurrentOrFirst(): void {
        if (!root.nState.searchOpen)
            navLocations.selectCurrentOrFirst();
    }

    function isInsideSearchRegion(item: Item, x: real, y: real): bool {
        if (!item)
            return false;

        const pt = root.mapFromItem(item, x, y);
        if (pt.x < 0 || pt.x > root.width || pt.y < 0 || pt.y > root.height)
            return false;

        const searchPt = searchField.mapFromItem(root, pt.x, pt.y);
        if (searchPt.x >= 0 && searchPt.x <= searchField.width &&
            searchPt.y >= 0 && searchPt.y <= searchField.height) {
            return true;
        }

        if (root.nState.searchOpen && searchResults.visible) {
            const resultsPt = searchResults.mapFromItem(root, pt.x, pt.y);
            if (resultsPt.x >= 0 && resultsPt.x <= searchResults.width &&
                resultsPt.y >= 0 && resultsPt.y <= searchResults.height) {
                return true;
            }
        }

        return false;
    }

    spacing: Tokens.spacing.medium

    SearchBar {
        id: searchField

        z: 1
        Layout.fillWidth: true
        Layout.preferredHeight: 46

        placeholderText: qsTr("Press / to Search")
        font: Tokens.font.body.medium

        bg.color: Colours.tPalette.m3surfaceContainerLowest
        bg.border.color: Colours.palette.m3outlineVariant
        searchIcon.fontStyle: Tokens.font.icon.medium
        searchIcon.anchors.leftMargin: Tokens.padding.largeIncreased
        clearIcon.font: Tokens.font.icon.medium
        clearIcon.padding: Tokens.padding.extraSmall

        onTextChanged: {
            if (text === "")
                root.clearQuery();
            else
                searchDebounce.restart();
        }

        Keys.onEscapePressed: event => {
            if (searchField.text !== "")
                searchField.clear();
            root.clearSearchFocus();
            event.accepted = true;
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Backspace && searchField.text === "") {
                root.clearSearchFocus();
                event.accepted = true;
            }
        }

        Keys.onReturnPressed: {
            root.activateSelected();
            root.clearSearchFocus();
        }

        Keys.onEnterPressed: {
            root.activateSelected();
            root.clearSearchFocus();
        }

        Keys.onRightPressed: event => {
            if (!root.nState.searchOpen && searchField.text === "") {
                root.activateSelected();
                root.clearSearchFocus();
                event.accepted = true;
            }
        }

        Keys.onUpPressed: root.moveUp()
        Keys.onDownPressed: root.moveDown()

        Behavior on bg.border.color {
            CAnim {}
        }

        Binding {
            target: root.nState
            property: "searchOpen"
            value: searchField.text.length > 0
        }

        Connections {
            function onSearchQueryChanged() {
                if (root.nState.searchQuery !== searchField.text) {
                    searchField.text = root.nState.searchQuery;
                    if (root.nState.searchQuery === "")
                        root.clearSearchFocus();
                }
            }

            target: root.nState
        }

        Timer {
            id: searchDebounce

            interval: 300
            onTriggered: root.publishQuery()
        }
    }

    NavLocations {
        id: navLocations

        visible: !root.nState.searchOpen

        Layout.fillWidth: true
        Layout.fillHeight: true
        nState: root.nState
    }

    SearchResults {
        id: searchResults

        visible: root.nState.searchOpen

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: -topMargin
        Layout.bottomMargin: -bottomMargin
        nState: root.nState

        onEntrySelected: (entry) => root.searchResultSelected(entry)
    }
}
