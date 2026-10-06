pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ConnectedRect {
    id: root

    property alias label: label.text
    property string subtext
    // Key in GlobalConfig.bar.previewScales/previewFontScales; empty disables the reset buttons
    property string resetKey: ""

    property real scaleValue
    property real scaleFrom: 0
    property real scaleTo: 99
    property real scaleStepSize: 1
    
    property real fontValue
    property real fontFrom: 0
    property real fontTo: 99
    property real fontStepSize: 1

    // Column geometry, mirrored by the page header so every column lines up.
    // Explicit preferred widths keep the sum equal to the row width so the
    // layout never squeezes the label column below its 30% share.
    readonly property real labelW: Math.round(rowLayout.width * 0.3)
    readonly property real colW: Math.max(0, (rowLayout.width - labelW - Tokens.spacing.extraSmall * 4 - resetScale.implicitWidth * 2) / 2)

    signal scaleMoved(value: real)
    signal fontMoved(value: real)

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins * 2

    RowLayout {
        id: rowLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        // Tight gaps so the reset buttons sit close to the sliders and the
        // two value columns keep as much width as possible
        spacing: Tokens.spacing.extraSmall

        ColumnLayout {
            id: labelCol

            // Fixed share of the row: long labels elide instead of pushing the columns
            Layout.preferredWidth: root.labelW
            spacing: 0

            StyledText {
                id: label
                Layout.fillWidth: true

                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtext
                text: root.subtext
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        CustomSpinBox {
            id: scaleBox

            // Splits the remaining width with the Font column so every row lines up
            Layout.preferredWidth: root.colW
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            min: root.scaleFrom
            max: root.scaleTo
            step: root.scaleStepSize
            value: root.scaleValue
            onValueModified: v => root.scaleMoved(v)
        }

        SettingResetButton {
            id: resetScale

            Layout.alignment: Qt.AlignVCenter
            options: root.resetKey !== "" ? ({
                customGet: () => GlobalConfig.bar.previewScales[root.resetKey],
                customDef: 0.0,
                customSet: v => {
                    GlobalConfig.bar.previewScales[root.resetKey] = v;
                }
            }) : null
        }

        CustomSpinBox {
            id: fontBox

            Layout.preferredWidth: root.colW
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            min: root.fontFrom
            max: root.fontTo
            step: root.fontStepSize
            value: root.fontValue
            onValueModified: v => root.fontMoved(v)
        }

        SettingResetButton {
            Layout.alignment: Qt.AlignVCenter
            options: root.resetKey !== "" ? ({
                customGet: () => GlobalConfig.bar.previewFontScales[root.resetKey],
                customDef: 0.0,
                customSet: v => {
                    GlobalConfig.bar.previewFontScales[root.resetKey] = v;
                }
            }) : null
        }
    }

    Connections {
        target: root

        function onScaleValueChanged() {
            if (scaleBox.value !== root.scaleValue) {
                scaleBox.value = root.scaleValue;
            }
        }

        function onFontValueChanged() {
            if (fontBox.value !== root.fontValue) {
                fontBox.value = root.fontValue;
            }
        }
    }
}
