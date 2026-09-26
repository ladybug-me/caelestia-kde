pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

MouseArea {
    id: root

    enum Side {
        Top,
        Bottom,
        Left,
        Right
    }

    required property Item attachTo
    property int attachSideX: Menu.Right
    property int attachSideY: Menu.Bottom
    property int thisSideX: Menu.Right
    property int thisSideY: Menu.Top
    property real marginX
    property real marginY

    property list<MenuItem> items
    property var dynamicModel: items
    property MenuItem active: dynamicModel[0] ?? null
    property bool expanded
    property bool rightClickReposition: false
    property real maxHeight: 320
    readonly property alias backgroundItem: menu
    property bool transparentBackground: false

    signal itemSelected(item: MenuItem)
    signal rightClickedAt(real x, real y)

    parent: {
        let node = root.attachTo;
        let interactionsNode = null;
        
        while (node && node.parent) {
            if (node.utilitiesShortcutActive !== undefined) {
                interactionsNode = node;
            }
            node = node.parent;
        }

        if (interactionsNode) {
            return interactionsNode;
        }

        return node || root.parent;
    }
    anchors.fill: parent

    enabled: expanded
    acceptedButtons: rightClickReposition ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
    onClicked: mouse => {
        if (rightClickReposition && mouse.button === Qt.RightButton) {
            rightClickedAt(mouse.x, mouse.y);
            return;
        }
        expanded = false;
    }

    opacity: expanded ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    TransformWatcher {
        id: watcher

        a: root.parent
        b: root.attachTo
    }

    Elevation {
        id: menu

        property string vAnchor: "none"
        property string hAnchor: "none"
        property real offsetScale: 1 - animScale
        property real animScale: root.expanded ? 1 : 0.0

        x: {
            watcher.transform; // mapToItem is not reactive so this forces updates
            const item = root.attachTo;
            if (!item || !root.parent)
                return 0;
            let off = root.attachSideX === Menu.Left ? 0 : item.width;
            if (root.thisSideX === Menu.Right)
                off -= width;
            const pt = item.mapToItem(root.parent, off, 0);
            return (pt ? pt.x : 0) + root.marginX;
        }
        y: {
            watcher.transform; // mapToItem is not reactive so this forces updates
            const item = root.attachTo;
            if (!item || !root.parent)
                return 0;
            let off = root.attachSideY === Menu.Top ? 0 : item.height;
            if (root.thisSideY === Menu.Bottom)
                off -= height;
            const pt = item.mapToItem(root.parent, 0, off);
            return (pt ? pt.y : 0) + root.marginY;
        }

        radius: Tokens.rounding.large
        level: root.transparentBackground ? 0 : 2
        implicitWidth: Math.max(200, column.implicitWidth + Tokens.padding.extraSmall * 2)
        implicitHeight: Math.min(root.maxHeight, column.implicitHeight + Tokens.padding.extraSmall * 2)
        width: implicitWidth
        height: implicitHeight * animScale

        Behavior on animScale {
            Anim {}
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onWheel: e => e.accepted = true
            onClicked: {}
        }

        StyledRect {
            y: root.thisSideY === Menu.Bottom ? menu.height - menu.implicitHeight : 0
            width: menu.implicitWidth
            height: menu.implicitHeight
            
            transform: Scale {
                yScale: menu.animScale
                origin.y: root.thisSideY === Menu.Bottom ? menu.implicitHeight : 0
            }
            
            radius: parent.radius
            // Fade alpha to 0 instead of the literal "transparent" string, which
            // would animate RGB through black via StyledRect's inherited
            // Behavior on color.
            color: root.transparentBackground
                ? Qt.alpha(Colours.palette.m3surfaceContainerLow, 0)
                : (GlobalConfig.appearance.pitchBlack
                    ? "#000000"
                    : Colours.palette.m3surfaceContainerLow)

            Flickable {
                id: flickable

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                contentWidth: width
                contentHeight: column.implicitHeight
                clip: true

                interactive: contentHeight > height

                ScrollBar.vertical: StyledScrollBar {
                    flickable: flickable
                }

                ColumnLayout {
                    id: column

                    width: parent.width
                    spacing: 0

                    Repeater {
                        id: repeater

                        model: root.dynamicModel

                    StyledRect {
                        id: item

                        required property int index
                        required property MenuItem modelData
                        readonly property bool active: modelData === root?.active

                        visible: modelData?.visible ?? false

                        Layout.fillWidth: true
                        implicitWidth: menuOptionRow.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: visible ? menuOptionRow.implicitHeight + Tokens.padding.medium * 2 : 0


                        radius: active ? Tokens.rounding.medium : Tokens.rounding.extraSmall
                        topLeftRadius: index === 0 ? Tokens.rounding.medium : radius
                        topRightRadius: index === 0 ? Tokens.rounding.medium : radius
                        bottomLeftRadius: index === repeater?.count - 1 ? Tokens.rounding.medium : radius
                        bottomRightRadius: index === repeater?.count - 1 ? Tokens.rounding.medium : radius

                        color: "transparent"

                        Behavior on radius {
                            Anim {}
                        }

                        StateLayer {
                            topLeftRadius: parent.topLeftRadius
                            topRightRadius: parent.topRightRadius
                            bottomLeftRadius: parent.bottomLeftRadius
                            bottomRightRadius: parent.bottomRightRadius

                            color: Colours.palette.m3onSurface
                            disabled: !root.expanded
                            onClicked: {
                                root.itemSelected(item.modelData);
                                root.active = item.modelData;
                                item.modelData.clicked();
                                root.expanded = false;
                            }
                        }

                        RowLayout {
                            id: menuOptionRow

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                Layout.alignment: Qt.AlignVCenter
                                text: item.modelData?.icon ?? ""
                                color: Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                text: item.modelData?.text ?? ""
                                color: Colours.palette.m3onSurface
                            }

                            Loader {
                                asynchronous: true
                                Layout.alignment: Qt.AlignVCenter
                                active: item.modelData?.trailingIcon.length > 0
                                visible: active

                                sourceComponent: MaterialIcon {
                                    text: item.modelData.trailingIcon
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }
        }
    }
}
