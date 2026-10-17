import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ConnectedRect {
    id: root

    property alias label: label.text
    property Component labelComponent
    property string subtext
    property string icon
    property alias menuItems: splitButton.menuItems
    property alias active: splitButton.active
    property alias fallbackText: splitButton.fallbackText
    property alias fallbackIcon: splitButton.fallbackIcon
    property alias menuOnTop: splitButton.menuOnTop
    property bool reorderable: false
    property bool highlight: false
    property real liftY: 0

    signal reorderStart()
    signal reorderDrag(real sceneY)
    signal reorderDrop()

    signal selected(item: MenuItem)

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins * 2
    clip: false
    z: (splitButton.expanded || root.highlight) ? 1 : 0
    transform: Translate {
        y: root.liftY
    }

    StyledRect {
        anchors.fill: parent
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        color: Colours.tPalette.m3surfaceContainerHigh
        opacity: root.highlight ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }
    }

    RowLayout {
        id: rowLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.reorderable
            visible: active

            sourceComponent: Item {
                implicitWidth: handleIcon.implicitWidth
                implicitHeight: handleIcon.implicitHeight

                MaterialIcon {
                    id: handleIcon

                    text: "drag_indicator"
                    color: Colours.palette.m3onSurfaceVariant
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.OpenHandCursor
                    preventStealing: true
                    drag.target: handleGrab
                    drag.axis: Drag.YAxis
                    onPressed: root.reorderStart()
                    onPositionChanged: mouse => {
                        if (pressed)
                            root.reorderDrag(mapToItem(null, mouse.x, mouse.y).y);
                    }
                    onReleased: root.reorderDrop()
                    onCanceled: root.reorderDrop()
                }

                Item {
                    id: handleGrab

                    visible: false
                }
            }
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: !!root.icon
            visible: active

            sourceComponent: IconImage {
                implicitSize: Tokens.font.icon.large.pointSize * 1.5
                source: root.icon
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: label

                Layout.fillWidth: true
                visible: !root.labelComponent
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            Loader {
                id: labelLoader

                Layout.fillWidth: true
                active: !!root.labelComponent
                visible: active
                sourceComponent: root.labelComponent
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtext && !root.labelComponent
                text: root.subtext
                color: Colours.palette.m3onSurfaceVariant
                font: NexusStyle.secondaryFont
                elide: Text.ElideRight
            }
        }

        SplitButton {
            id: splitButton

            type: SplitButton.Tonal
            stateLayer.onClicked: splitButton.expanded = !splitButton.expanded
            menu.onItemSelected: item => root.selected(item)
        }
    }
}
