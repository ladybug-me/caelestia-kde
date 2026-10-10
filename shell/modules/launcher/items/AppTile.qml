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
    readonly property bool simple: Config.launcher.browseLayout === LauncherBrowseLayout.Simple
    readonly property bool hovered: tileArea.containsMouse && nameMetrics.advanceWidth > name.width
    readonly property bool flipped: root.hovered && Config.launcher.nameOverflow === LauncherNameOverflow.Flip
    readonly property bool shrunk: root.hovered && Config.launcher.nameOverflow === LauncherNameOverflow.Shrink
    readonly property bool tooltipShown: Config.launcher.nameOverflow === LauncherNameOverflow.Flip ? fullName.truncated : name.truncated
    readonly property int nameLines: nameMetrics.height > 0 ? Math.max(1, Math.floor((root.implicitHeight - Tokens.spacing.small) / nameMetrics.height)) : 1
    readonly property int baseIconSize: Math.round(root.implicitWidth * 0.42)

    implicitWidth: Tokens.sizes.launcher.browseTileWidth
    implicitHeight: Tokens.sizes.launcher.browseTileHeight

    TextMetrics {
        id: nameMetrics

        font: name.font
        text: name.text
    }

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

    StateLayer {
        id: tileArea

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

        ToolTip.visible: tileArea.containsMouse && !favArea.containsMouse && root.tooltipShown
        ToolTip.text: root.modelData?.name ?? ""
    }

    Item {
        id: page

        anchors.fill: parent
        clip: true

        Item {
            id: frontFace

            width: page.width
            height: page.height
            y: root.flipped ? -height : 0

            Behavior on y {
                NumberAnimation {
                    duration: Tokens.anim.durations.expressiveFastSpatial
                    easing.type: Easing.OutBack
                }
            }

            Column {
                id: content

                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                Item {
                    id: iconBox

                    anchors.horizontalCenter: parent.horizontalCenter

                    implicitWidth: root.baseIconSize
                    implicitHeight: root.shrunk ? Math.round(root.baseIconSize / 2) : root.baseIconSize

                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: Tokens.anim.durations.expressiveFastSpatial
                            easing.type: Easing.OutBack
                        }
                    }

                    IconImage {
                        id: icon

                        anchors.centerIn: parent
                        asynchronous: true
                        source: WinIcons.sourceFor(root.modelData, "", root.modelData?.id ?? "", 0)
                        implicitSize: root.baseIconSize
                        scale: iconBox.height / root.baseIconSize
                    }
                }

                Item {
                    id: nameBox

                    anchors.horizontalCenter: parent.horizontalCenter
                    clip: true
                    implicitWidth: name.width
                    implicitHeight: name.implicitHeight

                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: Tokens.anim.durations.expressiveFastSpatial
                            easing.type: Easing.OutBack
                        }
                    }

                    StyledText {
                        id: name

                        text: root.modelData?.name ?? ""
                        color: root.selected ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                        font: root.simple ? Tokens.font.label.builders.medium.size(9).build() : Tokens.font.label.large
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        maximumLineCount: root.shrunk ? 2 : 1
                        width: root.implicitWidth - Tokens.padding.medium * 2
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            MaterialIcon {
                id: favIcon

                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Tokens.spacing.extraSmall
                anchors.rightMargin: Tokens.spacing.extraSmall

                width: 22
                height: 22
                fontStyle: Tokens.font.icon.small

                opacity: ((root.simple ? tileArea.containsMouse : root.isFavourite) || favArea.containsMouse) ? 1 : 0
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
                    disabled: root.flipped
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

        StyledText {
            id: fullName

            anchors.horizontalCenter: parent.horizontalCenter
            width: root.implicitWidth - Tokens.padding.medium * 2
            text: root.modelData?.name ?? ""
            color: root.selected ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
            font: name.font
            elide: Text.ElideRight
            wrapMode: Text.Wrap
            maximumLineCount: root.nameLines
            horizontalAlignment: Text.AlignHCenter
            y: root.flipped ? (page.height - height) / 2 : page.height

            Behavior on y {
                NumberAnimation {
                    duration: Tokens.anim.durations.expressiveFastSpatial
                    easing.type: Easing.OutBack
                }
            }
        }
    }
}
