pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Components
import qs.components
import qs.services

Item {
    id: root

    property var options

    readonly property bool active: root.options !== null && root.options !== undefined
    readonly property var current: root.active ? root.options.node[root.options.setting] : null
    readonly property var fallback: root.active ? root.options.node.descriptorFor(root.options.setting).defaultValue : null
    readonly property bool dirty: {
        if (!root.active)
            return false;
        if (typeof root.current === "number" && typeof root.fallback === "number")
            return Math.abs(root.current - root.fallback) > 0.005;
        return root.current !== root.fallback;
    }

    visible: root.dirty
    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: "restart_alt"
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.medium
    }

    CustomMouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.options.node.resetOption(root.options.setting)
    }
}
