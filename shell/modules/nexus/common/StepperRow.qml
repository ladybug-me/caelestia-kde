pragma ComponentBehavior: Bound

import QtQuick
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
    property var reset
    property real value
    property real from: 0
    property real to: 99
    property real stepSize: 1

    signal moved(value: real)


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

        CustomMouseArea {
            function onWheel(event: WheelEvent) {
                const step = root.stepSize;
                const decimals = step < 1 ? Math.max(1, Math.ceil(-Math.log10(step))) : 0;

                if (event.angleDelta.y > 0) {
                    let v = Math.min(root.to, root.value + step);
                    v = Math.round(v * Math.pow(10, decimals)) / Math.pow(10, decimals);
                    if (v !== root.value) root.moved(v);
                } else if (event.angleDelta.y < 0) {
                    let v = Math.max(root.from, root.value - step);
                    v = Math.round(v * Math.pow(10, decimals)) / Math.pow(10, decimals);
                    if (v !== root.value) root.moved(v);
                }
            }

            acceptedButtons: Qt.NoButton

            implicitWidth: spinBox.implicitWidth
            implicitHeight: spinBox.implicitHeight

            CustomSpinBox {
                id: spinBox

                anchors.fill: parent

                min: root.from
                max: root.to
                step: root.stepSize
                value: root.value
                onValueModified: v => root.moved(v)
            }
        }

        SettingResetButton {
            Layout.alignment: Qt.AlignVCenter
            options: root.reset
        }
    }
}
