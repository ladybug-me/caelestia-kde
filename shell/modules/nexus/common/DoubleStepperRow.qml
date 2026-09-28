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
    
    property real scaleValue
    property real scaleFrom: 0
    property real scaleTo: 99
    property real scaleStepSize: 1
    
    property real fontValue
    property real fontFrom: 0
    property real fontTo: 99
    property real fontStepSize: 1

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
        spacing: Tokens.spacing.medium

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
                visible: root.subtext
                text: root.subtext
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        CustomSpinBox {
            id: scaleBox

            min: root.scaleFrom
            max: root.scaleTo
            step: root.scaleStepSize
            value: root.scaleValue
            onValueModified: v => root.scaleMoved(v)
        }
        
        CustomSpinBox {
            id: fontBox

            min: root.fontFrom
            max: root.fontTo
            step: root.fontStepSize
            value: root.fontValue
            onValueModified: v => root.fontMoved(v)
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
