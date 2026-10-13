pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property alias layout: layout
    readonly property alias items: items
    readonly property alias expandIcon: expandIcon

    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property int spacing: Config.bar.tray.background ? Tokens.spacing.small : 0

    property bool expanded
    property bool pinned: false
    property var popouts
    readonly property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"
    readonly property int barThickness: Math.round(Tokens.sizes.bar.innerWidth * Math.max(0.6, !isNaN(Config.bar.scale) ? Config.bar.scale : 1.0))

    readonly property var trayItems: TrayRegistry.trayItems
    readonly property int collapsedCount: root.trayItems.filter(i => !GlobalConfig.bar.tray.alwaysVisible.includes(i.id)).length
    readonly property bool showArrow: Config.bar.tray.compact && root.collapsedCount > 0

    readonly property real nonAnimHeight: {
        if (isHorizontal)
            return barThickness;
        const arrow = root.showArrow ? expandIcon.implicitHeight + (layout.implicitHeight > 0 ? spacing : 0) : 0;
        return layout.implicitHeight + arrow + padding * 2;
    }

    readonly property real nonAnimWidth: {
        if (!isHorizontal)
            return barThickness;
        const arrow = root.showArrow ? expandIcon.implicitWidth + (layout.implicitWidth > 0 ? spacing : 0) : 0;
        return layout.implicitWidth + arrow + padding * 2;
    }

    clip: true
    visible: height > 0

    implicitWidth: isHorizontal ? nonAnimWidth : barThickness
    implicitHeight: isHorizontal ? barThickness : nonAnimHeight

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, (Config.bar.tray.background && items.count > 0) ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    // icon-level
    // right-clicks stay with the icons themselves (their own handlers sit on top
    // of this one, so they win first).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (!root.popouts)
                return;
            root.popouts.currentName = "traycontext";
            root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
            root.popouts.hasCurrent = true;
            mouse.accepted = true;
        }
    }

    Grid {
        id: layout

        anchors.horizontalCenter: isHorizontal ? undefined : parent.horizontalCenter
        anchors.verticalCenter: isHorizontal ? parent.verticalCenter : undefined
        anchors.top: isHorizontal ? undefined : parent.top
        anchors.topMargin: isHorizontal ? 0 : root.padding
        anchors.left: isHorizontal ? parent.left : undefined
        anchors.leftMargin: isHorizontal ? root.padding : 0

        columns: isHorizontal ? -1 : 1
        rows: isHorizontal ? 1 : -1
        flow: isHorizontal ? Grid.LeftToRight : Grid.TopToBottom

        spacing: Tokens.spacing.small

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        Repeater {
            id: items

            model: ScriptModel {
                values: root.trayItems
            }

            TrayItem {
                required property int index

                trayIndex: index
                popouts: root.popouts
                isHorizontal: root.isHorizontal
                alwaysVisible: GlobalConfig.bar.tray.alwaysVisible.includes(modelData.id)
                visible: root.expanded || !Config.bar.tray.compact || alwaysVisible
            }
        }
    }

    Loader {
        id: expandIcon

        asynchronous: true

        anchors.horizontalCenter: isHorizontal ? undefined : parent.horizontalCenter
        anchors.verticalCenter: isHorizontal ? parent.verticalCenter : undefined
        anchors.bottom: isHorizontal ? undefined : parent.bottom
        anchors.right: isHorizontal ? parent.right : undefined

        active: root.showArrow

        sourceComponent: Item {
            implicitWidth: isHorizontal ? (expandIconInner.implicitWidth - Tokens.padding.small * 2) : expandIconInner.implicitWidth
            implicitHeight: isHorizontal ? expandIconInner.implicitHeight : (expandIconInner.implicitHeight - Tokens.padding.small * 2)

            TapHandler {
                onTapped: {
                    root.pinned = !root.pinned;
                    root.expanded = root.pinned;
                }
            }

            MaterialIcon {
                id: expandIconInner

                anchors.horizontalCenter: isHorizontal ? undefined : parent.horizontalCenter
                anchors.verticalCenter: isHorizontal ? parent.verticalCenter : undefined
                anchors.bottom: isHorizontal ? undefined : parent.bottom
                anchors.right: isHorizontal ? parent.right : undefined
                anchors.bottomMargin: isHorizontal ? 0 : (Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.extraSmall)
                anchors.rightMargin: isHorizontal ? (Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.extraSmall) : 0
                text: "expand_less"
                fontStyle: Tokens.font.icon.large
                rotation: isHorizontal ? (root.expanded ? 270 : 90) : (root.expanded ? 180 : 0)

                Behavior on rotation {
                    Anim {}
                }

                Behavior on anchors.bottomMargin {
                    enabled: !isHorizontal

                    Anim {}
                }

                Behavior on anchors.rightMargin {
                    enabled: isHorizontal

                    Anim {}
                }
            }
        }
    }

    Behavior on implicitHeight {
        enabled: !isHorizontal

        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Behavior on implicitWidth {
        enabled: isHorizontal

        Anim {
            type: Anim.DefaultSpatial
        }
    }
}
