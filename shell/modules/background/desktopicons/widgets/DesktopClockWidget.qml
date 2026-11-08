pragma ComponentBehavior: Bound

import "../.."
import QtQuick

DesktopWidget {
    id: root

    clip: true

    DesktopClock {
        anchors.fill: parent
        frame: root.frame
        controller: root.controller
    }
}
