pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

StyledRect {
    id: root

    property alias icon: icon.text
    property alias label: label.text
    property alias valueLabel: valueLabel.text
    property string subtext
    property real value
    property var reset
    property bool first
    property bool last
    property bool isSelected: false
    property bool iconClickable: false
    property bool spacious: false
    property bool roomyHeader: false

    signal moved(value: real)
    signal interaction(value: real)
    signal released(value: real)
    signal iconClicked

    function stepLeft(): void {
        const step = 0.05;
        const next = Math.max(0, Math.round((root.value - step) * 100) / 100);
        root.moved(next);
        root.interaction(next);
        root.released(next);
    }

    function stepRight(): void {
        const step = 0.05;
        const next = Math.min(1, Math.round((root.value + step) * 100) / 100);
        root.moved(next);
        root.interaction(next);
        root.released(next);
    }

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins + rowLayout.anchors.topMargin
    color: isSelected ? Colours.layer(Colours.palette.m3surfaceContainerHigh, 4) : Colours.tPalette.m3surfaceContainer
    border.width: isSelected ? 2 : 0
    border.color: Colours.palette.m3primary
    topLeftRadius: isSelected ? Tokens.rounding.extraLargeIncreased : first ? (spacious ? Tokens.rounding.extraLarge : Tokens.rounding.large) : Tokens.rounding.extraSmall
    topRightRadius: isSelected ? Tokens.rounding.extraLargeIncreased : first ? (spacious ? Tokens.rounding.extraLarge : Tokens.rounding.large) : Tokens.rounding.extraSmall
    bottomLeftRadius: isSelected ? Tokens.rounding.extraLargeIncreased : last ? (spacious ? Tokens.rounding.extraLarge : Tokens.rounding.large) : Tokens.rounding.extraSmall
    bottomRightRadius: isSelected ? Tokens.rounding.extraLargeIncreased : last ? (spacious ? Tokens.rounding.extraLarge : Tokens.rounding.large) : Tokens.rounding.extraSmall

    Behavior on topLeftRadius {
        Anim {}
    }
    Behavior on topRightRadius {
        Anim {}
    }
    Behavior on bottomLeftRadius {
        Anim {}
    }
    Behavior on bottomRightRadius {
        Anim {}
    }

    Behavior on color {
        CAnim {}
    }

    RowLayout {
        id: rowLayout

        anchors.fill: parent
        anchors.margins: spacious ? Tokens.padding.largeIncreased : Tokens.padding.medium
        anchors.topMargin: spacious ? Tokens.padding.large : Tokens.padding.small
        // Keep the same right inset as ToggleRow/StepperRow (12px) even when
        // spacious, so reset icons line up in one column across every row type.
        anchors.rightMargin: Tokens.padding.medium
        spacing: spacious ? Tokens.spacing.medium : Tokens.spacing.small

        MaterialIcon {
            id: icon

            visible: text !== ""
            color: root.enabled ? Colours.palette.m3onSurfaceVariant : Colours.disabledContent
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
                Layout.minimumHeight: root.roomyHeader ? 40 : 0
                spacing: Tokens.spacing.small

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        id: label

                        Layout.fillWidth: true
                        font: Tokens.font.body.small
                        color: root.enabled ? Colours.palette.m3onSurface : Colours.disabledContent
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.subtext !== ""
                        text: root.subtext
                        color: root.enabled ? Colours.palette.m3onSurfaceVariant : Colours.disabledContent
                        font: NexusStyle.secondaryFont
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    id: valueLabel

                    color: root.enabled ? Colours.palette.m3onSurfaceVariant : Colours.disabledContent
                    font: Tokens.font.body.small
                }

                SettingResetButton {
                    Layout.alignment: Qt.AlignVCenter
                    options: root.reset
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
