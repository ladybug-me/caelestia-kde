pragma ComponentBehavior: Bound

import QtQuick
import qs.components.controls

IconButton {
    id: root

    property var options

    readonly property bool active: root.options !== null && root.options !== undefined
    readonly property var current: root.active ? root.options.node[root.options.setting] : null
    readonly property var fallback: root.active ? root.options.node.descriptorFor(root.options.setting).defaultValue : null

    visible: root.active && root.current !== root.fallback
    icon: "restart_alt"
    type: IconButton.Text
    onClicked: {
        console.log("RESETDBG before=" + root.options.node[root.options.setting] + " def=" + root.fallback);
        root.options.node.resetOption(root.options.setting);
        console.log("RESETDBG after=" + root.options.node[root.options.setting]);
    }
}
