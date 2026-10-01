pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.launcher.items
import qs.modules.launcher.services

// The compact app browser: one scrolling list with the favourites on top, a
// divider, and every other app sorted by name below them. It has no category
// sidebar, and exposes the same interface as AppBrowserGrid for the callers
// that drive it (ContentList and the search field's key handling).
Item {
    id: root

    required property DrawerVisibilities visibilities
    required property real maxWidth

    readonly property var currentItem: root.itemAt(root.currentIndex)
    readonly property int count: root.favourites.length + root.others.length
    readonly property bool showSeparator: root.favourites.length > 0 && root.others.length > 0

    readonly property int padding: Tokens.padding.large
    readonly property int tileWidth: Tokens.sizes.launcher.browseTileWidth
    readonly property int tileHeight: Tokens.sizes.launcher.browseTileHeight
    readonly property int gridSpacing: Tokens.spacing.medium

    // Columns the flows end up with, so the arrow keys can move a row at a time.
    readonly property int columns: Math.max(1, Math.floor((root.implicitWidth - root.padding * 2 + root.gridSpacing) / (root.tileWidth + root.gridSpacing)))
    readonly property int favRows: Math.ceil(root.favourites.length / root.columns)
    readonly property int otherRows: Math.ceil(root.others.length / root.columns)

    property var favourites: []
    property var others: []
    property int currentIndex: 0

    function favouriteIds(): list<string> {
        return GlobalConfig.launcher.favouriteApps ?? [];
    }

    function refresh(): void {
        const all = Apps.allApps();
        const favIds = root.favouriteIds();
        const favs = all.filter(a => Strings.testRegexList(favIds, a.id));

        // Favourites keep the order they are written in shell.json; anything
        // matched by a regex but not named there goes after the named ones.
        const rank = a => {
            const i = favIds.indexOf(a.id);
            return i < 0 ? favIds.length : i;
        };
        favs.sort((a, b) => rank(a) - rank(b));

        root.favourites = favs;
        root.others = all.filter(a => !Strings.testRegexList(favIds, a.id)).sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""));

        if (root.currentIndex >= root.count)
            root.currentIndex = Math.max(0, root.count - 1);
    }

    function launch(app): void {
        Apps.launch(app);
        root.visibilities.launcher = false;
    }

    function selectTile(index: int): void {
        root.currentIndex = index;
    }

    function itemAt(index: int): Item {
        if (index < 0)
            return null;
        if (index < root.favourites.length)
            return favRepeater.itemAt(index)?.tile ?? null;
        return otherRepeater.itemAt(index - root.favourites.length)?.tile ?? null;
    }

    function moveBy(delta: int): void {
        if (root.count === 0)
            return;
        const from = root.currentIndex < 0 ? 0 : root.currentIndex;
        root.currentIndex = Math.max(0, Math.min(root.count - 1, from + delta));
        root.ensureVisible();
    }

    // Keyboard entry points, invoked from the search field's Keys handlers.
    function incrementCurrentIndex(): void { // Down
        root.moveBy(root.columns);
    }

    function decrementCurrentIndex(): void { // Up
        root.moveBy(-root.columns);
    }

    function moveLeft(): void {
        root.moveBy(-1);
    }

    function moveRight(): void {
        root.moveBy(1);
    }

    // There is no sidebar to hand focus to here, so Tab does what Enter does.
    function toggleFocus(): void {
        root.activateCurrent();
    }

    function activateCurrent(): void {
        const item = root.currentItem;
        if (item?.modelData)
            root.launch(item.modelData);
    }

    function openContextMenu(app: DesktopEntry, targetItem: Item): void {
        contextMenu.openFor(app, targetItem);
    }

    // Bring the highlighted tile into view when the arrow keys walk past it.
    function ensureVisible(): void {
        const item = root.currentItem;
        if (!item || !flick.height)
            return;
        const p = item.mapToItem(flick, 0, 0);
        if (p.y < root.padding)
            flick.contentY = Math.max(0, flick.contentY + p.y - root.padding);
        else if (p.y + item.height > flick.height - root.padding)
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + p.y + item.height - (flick.height - root.padding));
    }

    implicitWidth: Math.min(Tokens.sizes.launcher.browseWidth, root.maxWidth)
    implicitHeight: root.padding * 2 + (root.count === 0 ? root.tileHeight * 2 : root.favRows * (root.tileHeight + root.gridSpacing) + (root.showSeparator ? root.gridSpacing * 2 + 1 : 0) + root.otherRows * (root.tileHeight + root.gridSpacing))

    Component.onCompleted: {
        root.refresh();
        root.currentIndex = 0;
    }

    Connections {
        function onListChanged(): void {
            root.refresh();
        }

        target: Apps
    }

    Connections {
        function onFavouriteAppsChanged(): void {
            root.refresh();
        }

        function onHiddenAppsChanged(): void {
            root.refresh();
        }

        target: GlobalConfig.launcher
    }

    AppContextMenu {
        id: contextMenu

        attachTo: root
        visibilities: root.visibilities
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentHeight: column.implicitHeight + root.padding * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column

            x: root.padding
            y: root.padding
            width: flick.width - root.padding * 2
            spacing: root.gridSpacing

            Flow {
                width: column.width
                spacing: root.gridSpacing

                Repeater {
                    id: favRepeater

                    model: root.favourites

                    delegate: Tile {
                        flatIndex: index
                    }
                }
            }

            Rectangle {
                width: column.width - Tokens.padding.medium * 2
                height: 1
                color: Colours.palette.m3outline
                opacity: 0.5
                visible: root.showSeparator

                anchors.horizontalCenter: parent.horizontalCenter
            }

            Flow {
                width: column.width
                spacing: root.gridSpacing

                Repeater {
                    id: otherRepeater

                    model: root.others

                    delegate: Tile {
                        flatIndex: root.favourites.length + index
                    }
                }
            }
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: flick
        }
    }

    // The two sections are separate repeaters, so a tile's index has to be its
    // position in the flattened list: the arrow keys and the highlight follow
    // that, and would otherwise jump between the sections.
    component Tile: Item {
        id: tileWrapper

        required property var modelData
        required property int index

        property int flatIndex: index
        property alias tile: innerTile

        implicitWidth: innerTile.implicitWidth
        implicitHeight: innerTile.implicitHeight

        AppTile {
            id: innerTile

            modelData: tileWrapper.modelData
            index: tileWrapper.flatIndex
            selected: root.currentIndex === tileWrapper.flatIndex
            browser: root
        }
    }
}
