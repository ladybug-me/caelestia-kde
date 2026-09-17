pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property DesktopEntry modelData
    required property int index
    required property bool selected
    required property var browser

    readonly property bool isFavourite: root.modelData && Strings.testRegexList(GlobalConfig.launcher.favouriteApps, root.modelData.id)
    readonly property bool favouriteByRegex: root.modelData && !((GlobalConfig.launcher.favouriteApps ?? []).includes(root.modelData.id)) && root.isFavourite

    implicitWidth: Tokens.sizes.launcher.browseTileWidth
    implicitHeight: Tokens.sizes.launcher.browseTileHeight

    // Selected highlight
    StyledRect {
        anchors.fill: parent
        anchors.margins: Tokens.spacing.extraSmall
        radius: Tokens.rounding.large
        color: Colours.palette.m3primary
        opacity: root.selected ? 0.14 : 0

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }
    }

    // Hover ripple + click to launch / right click for context menu
    StateLayer {
        anchors.fill: parent
        radius: Tokens.rounding.large
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onContainsMouseChanged: {
            if (containsMouse)
                root.browser.selectTile(root.index);
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.browser.openContextMenu(root.modelData, root);
            } else {
                root.browser.launch(root.modelData);
            }
        }
    }

    // Icon + label
    Column {
        id: content

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        IconImage {
            id: icon

            anchors.horizontalCenter: parent.horizontalCenter
            asynchronous: false // FIX 759: unsafe with KIconLoader
            source: Quickshell.iconPath(root.modelData?.icon, "image-missing")
            implicitSize: Math.round(root.implicitWidth * 0.42)
        }

        StyledText {
            id: name

            anchors.horizontalCenter: parent.horizontalCenter
            text: root.modelData?.name ?? ""
            color: root.selected ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.large
            elide: Text.ElideRight
            maximumLineCount: 1
            width: root.implicitWidth - Tokens.padding.medium * 2
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // Favourite toggle (shown on hover, or persistently when favourited)
    MaterialIcon {
        id: favIcon

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.extraSmall
        anchors.rightMargin: Tokens.spacing.extraSmall

        width: 22
        height: 22
        fontStyle: Tokens.font.icon.small

        opacity: (root.isFavourite || favArea.containsMouse) ? 1 : 0
        text: root.isFavourite ? "favorite" : "favorite_border"
        fill: root.isFavourite ? 1 : 0
        color: root.favouriteByRegex ? Colours.palette.m3outline : (root.isFavourite ? Colours.palette.m3primary : (favArea.containsMouse ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant))

        Behavior on color {
            CAnim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }

        StateLayer {
            id: favArea

            anchors.fill: undefined
            anchors.centerIn: parent
            implicitWidth: 26
            implicitHeight: 26
            radius: Tokens.rounding.full
            cursorShape: root.favouriteByRegex ? Qt.ArrowCursor : Qt.PointingHandCursor

            onClicked: {
                if (root.favouriteByRegex)
                    return;
                const appId = root.modelData?.id;
                if (!appId)
                    return;
                const favApps = GlobalConfig.launcher.favouriteApps ? [...GlobalConfig.launcher.favouriteApps] : [];
                if (Strings.testRegexList(favApps, appId)) {
                    const idx = favApps.indexOf(appId);
                    if (idx !== -1)
                        favApps.splice(idx, 1);
                } else {
                    favApps.push(appId);
                }
                GlobalConfig.launcher.favouriteApps = favApps;
                root.browser.refresh();
            }

            ToolTip.visible: favArea.containsMouse && root.favouriteByRegex
            ToolTip.text: qsTr("Matched by a regex in favouriteApps - edit the config file to change")
        }
    }
}
