pragma ComponentBehavior: Bound

import "../.."
import QtQuick

Item {
    id: root

    property var frame: null
    property var controller: null

    DesktopShapes {
        anchors.fill: parent
        frame: root.frame
        controller: root.controller
    }
}
