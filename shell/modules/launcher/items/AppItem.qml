pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.launcher.services

Item {
    id: root

    required property DesktopEntry modelData
    required property DrawerVisibilities visibilities
    required property var list

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        id: stateLayer

        radius: Tokens.rounding.large
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.list.openContextMenu(root.modelData, root);
            } else {
                Apps.launch(root.modelData);
                root.visibilities.launcher = false;
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        IconImage {
            id: icon

            asynchronous: false
            source: WinIcons.sourceFor(root.modelData, "", root.modelData?.id ?? "", 0)
            implicitSize: Math.max(1, parent.height * 0.8)

            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width - 60
            implicitHeight: name.implicitHeight + comment.implicitHeight

            StyledText {
                id: name

                text: root.modelData?.name ?? ""
                font: Tokens.font.body.medium
            }

            StyledText {
                id: comment

                text: (root.modelData?.comment || root.modelData?.genericName || root.modelData?.name) ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3outline

                elide: Text.ElideRight
                width: root.width - icon.width - 60 - Tokens.rounding.extraLargeIncreased

                anchors.top: name.bottom
            }
        }

        StateLayer {
            id: favIcon

            anchors.fill: undefined
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            width: 32
            height: 32
            radius: Tokens.rounding.full

            onClicked: {
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
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: Strings.testRegexList(GlobalConfig.launcher.favouriteApps, root.modelData?.id) ? "favorite" : "favorite_border"
                fill: Strings.testRegexList(GlobalConfig.launcher.favouriteApps, root.modelData?.id) ? 1 : 0
                color: favIcon.containsMouse ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

                Behavior on color {
                    CAnim {}
                }
            }
        }
    }
}
