pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property var wallsList: {
        const category = root.nState ? root.nState.selectedWallpaperCategory : "";
        let walls = Wallpapers.list.filter(w => Wallpapers.getCategoryFor(w) === category);
        const filter = root.nState ? root.nState.wallpaperFilterType : "all";

        walls = walls.filter(w => {
            const isVid = Images.isVideo(w.name);
            const isGif = w.name.toLowerCase().endsWith(".gif");
            const isImg = Images.isValidImageByName(w.name) && !isGif;

            if (filter === "all") return true;
            if (filter === "video") return isVid;
            if (filter === "gif") return isGif;
            if (filter === "image") return isImg;
            return false;
        });

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
