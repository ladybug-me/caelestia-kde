pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property bool checked: false
    property string accessibleLabel

    signal toggled()

    function toggle(): void {
        checked = !checked;
        toggled();
    }

    implicitWidth: 24
    implicitHeight: 24

    Accessible.role: Accessible.CheckBox
    Accessible.name: accessibleLabel
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onToggleAction: toggle()

    activeFocusOnTab: enabled
    Keys.onSpacePressed: toggle()

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.medium
        color: "transparent"
        border.width: 2
        border.color: !root.enabled ? Colours.disabledContainer : root.checked ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

        Behavior on border.color {
            CAnim {}
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: "check"
            fontStyle: Tokens.font.icon.builders.small.weight(Font.DemiBold).build()
            color: !root.enabled ? Colours.disabledContent : Colours.palette.m3primary
            scale: root.checked ? 1 : 0

            Behavior on scale {
                Anim {
                    type: Anim.EmphasizedSmall
                }
            }
        }
    }

    CustomMouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggle()
    }

    // The box is the control; the ring follows its own edge.
    StyledRect {
        anchors.fill: parent
        anchors.margins: -3

        radius: Tokens.rounding.medium
        border.width: 2
        border.color: Colours.palette.m3primary
        visible: root.activeFocus && root.activeFocusOnTab
    }
}
