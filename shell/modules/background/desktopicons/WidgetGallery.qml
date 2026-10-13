pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

// "Add Widget" panel: pick a widget and it lands where the menu was opened.
Item {
    id: root

    property var controller: null
    property bool open: false
    property point at
    property var cell: null

    function openAt(x: real, y: real, target: var): void {
        at = Qt.point(x, y);
        cell = target;
        open = true;
    }

    anchors.fill: parent
    visible: panel.opacity > 0

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.open = false
    }

    Elevation {
        id: panel

        x: Math.max(Tokens.padding.large, Math.min(root.width - width - Tokens.padding.large, root.at.x))
        y: Math.max(Tokens.padding.large, Math.min(root.height - height - Tokens.padding.large, root.at.y))
        width: content.implicitWidth + Tokens.padding.large * 2
        height: content.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        level: 2
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.9
        transformOrigin: Item.TopLeft

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        }

        StyledRect {
            anchors.fill: parent
            radius: parent.radius
            color: GlobalConfig.appearance.pitchBlack ? "#000000" : Colours.palette.m3surfaceContainerLow

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    text: qsTr("Add Widget")
                    font: Tokens.font.title.medium
                }

                GridLayout {
                    columns: 3
                    rowSpacing: Tokens.spacing.small
                    columnSpacing: Tokens.spacing.small

                    Repeater {
                        model: root.controller?.widgetCatalog?.types ?? []

                        StyledRect {
                            id: card

                            required property var modelData

                            implicitWidth: 150
                            implicitHeight: cardColumn.implicitHeight + Tokens.padding.large * 2
                            radius: Tokens.rounding.medium
                            color: cardArea.containsMouse ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainer

                            ColumnLayout {
                                id: cardColumn

                                anchors.centerIn: parent
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: card.modelData.icon
                                    color: Colours.palette.m3primary
                                    fontStyle: Tokens.font.icon.builders.extraLarge.build()
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: card.modelData.name
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: `${card.modelData.size.w} × ${card.modelData.size.h}`
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                }
                            }

                            MouseArea {
                                id: cardArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.open = false;
                                    root.controller.addWidget(card.modelData.type, root.cell);
                                }
                            }
                        }
                    }
                }

                StyledText {
                    text: qsTr("Drag a widget's corner to resize it; right-click for more")
                    color: Colours.palette.m3outline
                }
            }
        }
    }
}
