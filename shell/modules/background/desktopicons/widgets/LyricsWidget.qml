pragma ComponentBehavior: Bound

import "../.."
import QtQuick

DesktopWidget {
    id: root

    DesktopLyrics {
        anchors.fill: parent
        frame: root.frame
        controller: root.controller
    }
}
