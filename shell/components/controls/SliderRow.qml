pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    property alias icon: icon.text
    property alias label: label.text
    property alias valueLabel: valueLabel.text
    property string subtext
    property real value
    property bool first
    property bool last
    property bool iconClickable: false
    property bool spacious: false

    signal moved(value: real)
    signal interaction(value: real)
    signal released(value: real)
    signal iconClicked

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins + rowLayout.anchors.topMargin
    color: Colours.tPalette.m3surfaceContainer
    topLeftRadius: first ? (spacious ? Tokens.rounding.extraLarge : Tokens.rounding.large) : Tokens.rounding.extraSmall
    topRightRadius: first ? (spacious ? Tokens.rounding.extraLarge : Tokens.rounding.large) : Tokens.rounding.extraSmall
    bottomLeftRadius: last ? (spacious ? Tokens.rounding.extraLarge : Tokens.rounding.large) : Tokens.rounding.extraSmall
    bottomRightRadius: last ? (spacious ? Tokens.rounding.extraLarge : Tokens.rounding.large) : Tokens.rounding.extraSmall

    RowLayout {
        id: rowLayout

        anchors.fill: parent
        anchors.margins: spacious ? Tokens.padding.largeIncreased : Tokens.padding.medium
        anchors.topMargin: spacious ? Tokens.padding.large : Tokens.padding.small
        spacing: spacious ? Tokens.spacing.medium : Tokens.spacing.small

        MaterialIcon {
            id: icon

            visible: text !== ""
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: spacious ? Tokens.font.icon.medium : Tokens.font.icon.small

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                enabled: root.iconClickable
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.iconClicked()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: spacious ? Tokens.spacing.medium : Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        id: label

                        Layout.fillWidth: true
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.subtext !== ""
                        text: root.subtext
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    id: valueLabel

                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }

            CustomMouseArea {
                function onWheel(event: WheelEvent): void {
                    const step = GlobalConfig.services.audioIncrement;
                    if (event.angleDelta.y > 0)
                        root.moved(Math.min(1, root.value + step));
                    else if (event.angleDelta.y < 0)
                        root.moved(Math.max(0, root.value - step));
                }

                Layout.fillWidth: true
                implicitHeight: spacious ? Tokens.padding.medium * 2 : Tokens.padding.large

                StyledSlider {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: parent.implicitHeight

                    radius: Tokens.rounding.small
                    value: root.value
                    enabled: root.enabled
                    onInteraction: v => {
                        root.moved(v);
                        root.interaction(v);
                    }
                    onReleased: v => root.released(v)
                }
            }
        }
    }
}
