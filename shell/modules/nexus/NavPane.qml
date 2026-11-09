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

    // Both result panes search the index and build a delegate per hit, so the
    // query is published once typing pauses instead of on every keystroke.
    function publishQuery(): void {
        searchDebounce.stop();
        root.nState.searchQuery = searchField.text;
    }

    function clearQuery(): void {
        searchDebounce.stop();
        root.nState.searchQuery = "";
    }

    spacing: Tokens.spacing.large

    SearchBar {
        id: searchField

        z: 1
        Layout.fillWidth: true

        placeholderText: qsTr("Search settings")
        font: Tokens.font.body.large

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

        Keys.onReturnPressed: {
            if (root.nState.searchOpen) {
                root.publishQuery();
                searchResults.executeSelected();
            }
        }

        Keys.onUpPressed: {
            if (root.nState.searchOpen) {
                searchResults.moveUp();
            }
        }

        Keys.onDownPressed: {
            if (root.nState.searchOpen) {
                searchResults.moveDown();
            }
        }

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
                }
            }

            target: root.nState
        }

        Timer {
            id: searchDebounce

            interval: 400
            onTriggered: root.publishQuery()
        }
    }

    NavLocations {
        visible: !root.nState.searchOpen

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: -topMargin
        Layout.bottomMargin: -bottomMargin
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
    }
}
