pragma ComponentBehavior: Bound

import QtQuick
import qs.components.controls

IconButton {
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
    icon: "restart_alt"
    type: IconButton.Text
    onClicked: root.options.node.resetOption(root.options.setting)
}
