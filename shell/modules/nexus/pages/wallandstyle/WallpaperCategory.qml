pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Models
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property var wallsList: {
        const category = root.nState ? root.nState.selectedWallpaperCategory : "";
        let walls = Wallpapers.list.filter(w => Wallpapers.getCategoryFor(w) === category);
        walls.sort((a, b) => a.name.localeCompare(b.name));
        while (walls.length % Config.nexus.wallpapersPerRow !== 0)
            walls.push(null);
        return walls;
    }

    title: {
        const c = nState.selectedWallpaperCategory;
        return c.slice(0, 1).toUpperCase() + c.slice(1);
    }
    isSubPage: true
    scrollable: false

    headerActions: [
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
    ]

    ListView {
        id: gridList

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.cappedWidth
        clip: true

        model: root.wallsList.length > 0 ? Math.ceil(root.wallsList.length / Config.nexus.wallpapersPerRow) : 0
        spacing: Tokens.spacing.medium

        delegate: RowLayout {
            id: rowDel

            required property int index

            width: gridList.width
            spacing: Tokens.spacing.large

            Repeater {
                model: Config.nexus.wallpapersPerRow

                WallItem {
                    required property int index
                    readonly property int globalIndex: rowDel.index * Config.nexus.wallpapersPerRow + index
                    readonly property var modelData: root.wallsList[globalIndex]

                    opacity: modelData ? 1 : 0
                    enabled: !!modelData
                    Layout.fillWidth: true

                    source: String(modelData?.path ?? "")
                    text: modelData?.name ?? ""
                    onClicked: {
                        Wallpapers.setWallpaper(modelData.path);
                    }
                }
            }
        }
    }
}
