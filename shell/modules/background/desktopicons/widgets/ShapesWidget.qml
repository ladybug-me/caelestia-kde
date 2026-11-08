pragma ComponentBehavior: Bound

import ".."
import "../.."
import QtQuick

DesktopWidget {
    id: root

    DesktopShapes {
        anchors.fill: parent
        frame: root.frame
        controller: root.controller
    }
}
