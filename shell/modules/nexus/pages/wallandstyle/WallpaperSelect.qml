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
        const filter = root.nState ? root.nState.wallpaperFilterType : "all";

        for (const w of walls) {
            const isVid = Images.isVideo(w.name);
            const isGif = w.name.toLowerCase().endsWith(".gif");
            const isImg = Images.isValidImageByName(w.name) && !isGif;

            let matches = false;
            if (filter === "all") matches = true;
            else if (filter === "video" && isVid) matches = true;
            else if (filter === "gif" && isGif) matches = true;
            else if (filter === "image" && isImg) matches = true;

            if (!matches) continue;

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

    title: qsTr("Select wallpaper")
    isSubPage: true
    scrollable: false

    onSortColorChanged: {
        if (sortColor === "transparent") {
            wallpaperColors = ({});
            colorDistances = ({});
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

            Timer {
                id: sortDebouncer

                interval: 250
                onTriggered: {
                    root.analyzeColors();
                }
            }

            ButtonRow {
                Layout.bottomMargin: Tokens.spacing.medium
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.small

                IconTextButton {
                    icon: "photo_library"
                    text: qsTr("Browse")
                    font: Tokens.font.body.large
                    isRound: true
                    shapeMorph: true
                    horizontalPadding: Tokens.padding.extraLarge
                    verticalPadding: Tokens.padding.medium
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
                    font: Tokens.font.body.large
                    isRound: true
                    shapeMorph: true
                    horizontalPadding: Tokens.padding.extraLarge
                    verticalPadding: Tokens.padding.medium
                    type: IconTextButton.Tonal
                    onClicked: {
                        Wallpapers.setRandom();
                        root.nState.closeSubPage();
                    }
                }

                IconTextButton {
                    icon: "folder_open"
                    text: qsTr("Open folder")
                    font: Tokens.font.body.large
                    isRound: true
                    shapeMorph: true
                    horizontalPadding: Tokens.padding.extraLarge
                    verticalPadding: Tokens.padding.medium
                    type: IconTextButton.Tonal
                    onClicked: Quickshell.execDetached(["xdg-open", Paths.wallsdir])
                }
            }

            WallItem {
                Layout.topMargin: Tokens.spacing.medium
                imgHeight: Math.round(width * 0.3)
                radius: Tokens.rounding.extraLarge
                source: Wallpapers.fallback
                text: qsTr("Featured wallpaper")
                fillLabel: false
                onClicked: {
                    Wallpapers.setWallpaper(Wallpapers.fallback);
                    root.nState.closeSubPage();
                }
            }

            RowLayout {
                Layout.topMargin: Tokens.spacing.medium
                Layout.fillWidth: true
                z: typeFilterBtn.expanded ? 1 : 0

                Item {
                    Layout.fillWidth: true
                }

                Row {
                    spacing: Tokens.spacing.medium

                    Rectangle {
                        width: 36
                        height: 36
                        radius: Tokens.rounding.full
                        color: "#e53935"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 36
                            height: 36
                            radius: parent.radius
                            color: "transparent"
                            border.width: root.sortColor === "#e53935" ? 3 : 0
                            border.color: Colours.palette.m3onSurface
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: root.toggleSortColor("#e53935")
                        }
                    }

                    Rectangle {
                        width: 36
                        height: 36
                        radius: Tokens.rounding.full
                        color: "#1e88e5"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 36
                            height: 36
                            radius: parent.radius
                            color: "transparent"
                            border.width: root.sortColor === "#1e88e5" ? 3 : 0
                            border.color: Colours.palette.m3onSurface
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: root.toggleSortColor("#1e88e5")
                        }
                    }

                    Rectangle {
                        width: 36
                        height: 36
                        radius: Tokens.rounding.full
                        color: "#43a047"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 36
                            height: 36
                            radius: parent.radius
                            color: "transparent"
                            border.width: root.sortColor === "#43a047" ? 3 : 0
                            border.color: Colours.palette.m3onSurface
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: root.toggleSortColor("#43a047")
                        }
                    }

                    Rectangle {
                        width: 36
                        height: 36
                        radius: Tokens.rounding.full
                        color: "#fdd835"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 36
                            height: 36
                            radius: parent.radius
                            color: "transparent"
                            border.width: root.sortColor === "#fdd835" ? 3 : 0
                            border.color: Colours.palette.m3onSurface
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: root.toggleSortColor("#fdd835")
                        }
                    }

                    Rectangle {
                        width: 36
                        height: 36
                        radius: Tokens.rounding.full
                        color: "#8e24aa"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 36
                            height: 36
                            radius: parent.radius
                            color: "transparent"
                            border.width: root.sortColor === "#8e24aa" ? 3 : 0
                            border.color: Colours.palette.m3onSurface
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: root.toggleSortColor("#8e24aa")
                        }
                    }

                    Rectangle {
                        width: 36
                        height: 36
                        radius: Tokens.rounding.full
                        color: "#fb8c00"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 36
                            height: 36
                            radius: parent.radius
                            color: "transparent"
                            border.width: root.sortColor === "#fb8c00" ? 3 : 0
                            border.color: Colours.palette.m3onSurface
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: root.toggleSortColor("#fb8c00")
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                SplitButton {
                    id: typeFilterBtn

                    type: SplitButton.Tonal
                    fallbackIcon: "collections"
                    fallbackText: qsTr("All")
                    minLeftWidth: 100

                    menuItems: [
                        MenuItem {
                            property string filterValue: "all"

                            text: qsTr("All")
                            icon: "collections"
                            onClicked: {
                                if (root.nState) root.nState.wallpaperFilterType = "all"
                            }
                        },
                        MenuItem {
                            property string filterValue: "image"

                            text: qsTr("Images")
                            icon: "image"
                            onClicked: {
                                if (root.nState) root.nState.wallpaperFilterType = "image"
                            }
                        },
                        MenuItem {
                            property string filterValue: "gif"

                            text: qsTr("GIFs")
                            icon: "gif"
                            onClicked: {
                                if (root.nState) root.nState.wallpaperFilterType = "gif"
                            }
                        },
                        MenuItem {
                            property string filterValue: "video"

                            text: qsTr("Videos")
                            icon: "movie"
                            onClicked: {
                                if (root.nState) root.nState.wallpaperFilterType = "video"
                            }
                        }
                    ]

                    active: {
                        const f = root.nState ? root.nState.wallpaperFilterType : "all";
                        return menuItems.find(m => m.filterValue === f) ?? menuItems[0];
                    }
                }
            }

            StyledText {
                Layout.topMargin: Tokens.spacing.large
                text: qsTr("Local wallpapers")
                font: Tokens.font.title.small
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
                                    sortDebouncer.restart();
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
