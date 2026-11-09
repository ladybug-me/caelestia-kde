pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Components
import Caelestia.Config
import Caelestia.Images
import Caelestia.Models
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property color sortColor: "transparent"

    property var colorDistances: ({})

    property int sortVersion: 0

    property var wallpaperColors: ({})

    readonly property var sortColors: ["#e53935"
        , "#1e88e5"
        , "#43a047"
        , "#fdd835"
        , "#8e24aa"
        , "#fb8c00"
    ]

    property var wallsList: {
        const walls = Wallpapers.list;
        const baseDir = Paths.wallsdir;
        const categories = {};
        const list = [];

        for (const w of walls) {
            if (w.parentDir !== baseDir) {
                const category = Wallpapers.getCategoryFor(w);
                if (category && (!(category in categories) || categories[category].name.localeCompare(w.name) > 0))
                    categories[category] = w;
            } else {
                list.push(w);
            }
        }

        for (const cat in categories) {
            list.push(categories[cat]);
        }

        if (root.sortColor !== "transparent") {
            list.sort((a, b) => {
                const distA = root.colorDistances[a.path] ?? 999999;
                const distB = root.colorDistances[b.path] ?? 999999;
                return distA - distB;
            });
        } else {
            list.sort((a, b) => a.name.localeCompare(b.name));
        }

        while (list.length % Config.nexus.wallpapersPerRow !== 0)
            list.push(null);
        return list;
    }

    function colorDistance(c1: color, c2: color): real {
        const rMean = (c1.r + c2.r) / 2;
        const dr = c1.r - c2.r;
        const dg = c1.g - c2.g;
        const db = c1.b - c2.b;
        return Math.sqrt((2 + rMean) * dr * dr + 4 * dg * dg + (3 - rMean) * db * db);
    }

    function toggleSortColor(color: color) {
        if (root.sortColor === color) {
            root.sortColor = "transparent";
        } else {
            root.sortColor = color;
            root.analyzeColors();
        }
    }

    function analyzeColors() {
        const walls = Wallpapers.list;
        const baseDir = Paths.wallsdir;
        const newDistances = {};

        for (const w of walls) {
            if (w.parentDir !== baseDir)
                continue;

            const dominant = root.wallpaperColors[w.path];
            if (dominant === undefined)
                continue;

            newDistances[w.path] = colorDistance(dominant, root.sortColor);
        }

        root.colorDistances = newDistances;
        root.sortVersion++;
    }

    function restartSortDebouncer(): void {
        sortDebouncer.restart();
    }

    title: qsTr("Select wallpaper")
    isSubPage: true
    scrollable: false

    onSortColorChanged: {
        if (sortColor === "transparent") {
            wallpaperColors = ({});
            colorDistances = ({});
        }
    }

    Item {
        Timer {
            id: sortDebouncer

            interval: 250
            onTriggered: {
                root.analyzeColors();
            }
        }
    }

    ListView {
        id: gridList

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.cappedWidth
        clip: true
        spacing: Tokens.spacing.medium

        model: root.wallsList.length > 0 ? Math.ceil(root.wallsList.length / Config.nexus.wallpapersPerRow) : 0

        header: ColumnLayout {
            width: gridList.width
            spacing: Tokens.spacing.small

            WallItem {
                imgHeight: Math.round(width * 0.3)
                radius: Tokens.rounding.extraLarge
                source: Wallpapers.actualCurrent || Wallpapers.fallback
                text: qsTr("Current wallpaper")
                fillLabel: false
                clickable: false
            }

            RowLayout {
                Layout.topMargin: Tokens.spacing.medium
                Layout.bottomMargin: Tokens.spacing.large
                Layout.fillWidth: true
                z: typeFilterBtn.expanded ? 1 : 0

                Row {
                    spacing: Tokens.spacing.small

                    IconTextButton {
                        icon: "photo_library"
                        text: qsTr("Browse")
                        type: IconTextButton.Tonal
                        onClicked: browseDialog.open()

                        FileDialog {
                            id: browseDialog

                            title: qsTr("Select an image")
                            filterLabel: qsTr("Image files")
                            filters: Images.validImageExtensions
                            onAccepted: path => {
                                Wallpapers.setWallpaper(path);
                            }
                        }
                    }

                    IconTextButton {
                        icon: "shuffle"
                        text: qsTr("Random")
                        type: IconTextButton.Tonal
                        onClicked: Wallpapers.setRandom()
                    }

                    IconTextButton {
                        icon: "folder_open"
                        text: qsTr("Open folder")
                        type: IconTextButton.Tonal
                        onClicked: Quickshell.execDetached(["xdg-open", Paths.wallsdir])
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                SplitButton {
                    id: typeFilterBtn

                    type: SplitButton.Tonal
                    fallbackIcon: {
                        const f = Wallpapers.currentMediaFilter;
                        if (f === "Video") return "movie";
                        if (f === "Animated") return "gif";
                        if (f === "Image") return "image";
                        return "collections";
                    }
                    fallbackText: {
                        const f = Wallpapers.currentMediaFilter;
                        if (f === "Video") return qsTr("Videos");
                        if (f === "Animated") return qsTr("GIFs");
                        if (f === "Image") return qsTr("Images");
                        return qsTr("All");
                    }
                    minLeftWidth: 100

                    menuItems: [
                        MenuItem {
                            property string filterValue: "All"

                            text: qsTr("All")
                            icon: "collections"
                            onClicked: {
                                Wallpapers.currentMediaFilter = "All";
                            }
                        },
                        MenuItem {
                            property string filterValue: "Image"

                            text: qsTr("Images")
                            icon: "image"
                            onClicked: {
                                Wallpapers.currentMediaFilter = "Image";
                            }
                        },
                        MenuItem {
                            property string filterValue: "Animated"

                            text: qsTr("GIFs")
                            icon: "gif"
                            onClicked: {
                                Wallpapers.currentMediaFilter = "Animated";
                            }
                        },
                        MenuItem {
                            property string filterValue: "Video"

                            text: qsTr("Videos")
                            icon: "movie"
                            onClicked: {
                                Wallpapers.currentMediaFilter = "Video";
                            }
                        }
                    ]

                    active: {
                        const f = Wallpapers.currentMediaFilter;
                        for (let i = 0; i < menuItems.length; i++) {
                            if (menuItems[i].filterValue === f)
                                return menuItems[i];
                        }
                        return menuItems[0];
                    }

                    Component.onCompleted: {
                        for (let i = 0; i < menuItems.length; i++) {
                            if (menuItems[i].filterValue === Wallpapers.currentMediaFilter) {
                                active = menuItems[i];
                                return;
                            }
                        }
                    }

                    Connections {
                        function onCurrentMediaFilterChanged(): void {
                            for (let i = 0; i < typeFilterBtn.menuItems.length; i++) {
                                if (typeFilterBtn.menuItems[i].filterValue === Wallpapers.currentMediaFilter) {
                                    typeFilterBtn.active = typeFilterBtn.menuItems[i];
                                    return;
                                }
                            }
                            typeFilterBtn.active = typeFilterBtn.menuItems[0];
                        }

                        target: Wallpapers
                    }
                }
            }
        }

        delegate: RowLayout {
            id: rowDel

            required property int index

            width: gridList.width
            spacing: Tokens.spacing.large

            Repeater {
                model: Config.nexus.wallpapersPerRow

                WallItem {
                    id: wallItem

                    required property int index
                    readonly property int globalIndex: rowDel.index * Config.nexus.wallpapersPerRow + index
                    readonly property var modelData: root.wallsList[globalIndex]

                    opacity: modelData ? 1 : 0
                    enabled: !!modelData
                    Layout.fillWidth: true

                    isFolder: modelData && modelData.parentDir !== Paths.wallsdir
                    folderCount: {
                        if (!modelData || modelData.parentDir === Paths.wallsdir)
                            return 0;
                        const group = Wallpapers.grouped[Wallpapers.getCategoryFor(modelData)];
                        return group ? group.length : 0;
                    }

                    source: String(modelData?.path ?? "")
                    text: {
                        if (!modelData)
                            return "";

                        if (modelData.parentDir !== Paths.wallsdir) {
                            const category = Wallpapers.getCategoryFor(modelData);
                            return category.slice(0, 1).toUpperCase() + category.slice(1);
                        }
                        return modelData.name;
                    }
                    onClicked: {
                        if (modelData.parentDir !== Paths.wallsdir) {
                            root.nState.selectedWallpaperCategory = Wallpapers.getCategoryFor(modelData);
                            root.nState.openSubPage(2);
                        } else {
                            Wallpapers.setWallpaper(modelData.path);
                        }
                    }

                    ImageAnalyser {
                        id: colorAnalyzer

                        source: (root.sortColor !== "transparent" && wallItem.modelData && wallItem.modelData.parentDir === Paths.wallsdir) ? wallItem.modelData.path : ""
                        rescaleSize: 64
                        onDominantColourChanged: {
                            if (wallItem.modelData && dominantColour.a > 0) {
                                root.wallpaperColors[wallItem.modelData.path] = dominantColour;
                                if (root.sortColor !== "transparent") {
                                    root.restartSortDebouncer();
                                }
                            }
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true

            asynchronous: true
            active: root.wallsList.length === 0
            visible: active

            sourceComponent: StyledRect {
                color: Colours.tPalette.m3surfaceContainer
                radius: Tokens.rounding.extraLarge
                implicitHeight: noWallsLayout.implicitHeight + Tokens.padding.extraExtraLarge * 2

                ColumnLayout {
                    id: noWallsLayout

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No local wallpapers found")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.title.small
                    }
                }
            }
        }
    }
}
