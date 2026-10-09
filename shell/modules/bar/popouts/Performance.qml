pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.dashboard as DashPerf

// Performance popout: the full dashboard performance tab.
ColumnLayout {
    id: root

    required property var popouts

    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false

    width: Math.max(300, perfView.implicitWidth)
    spacing: Tokens.spacing.small

    Item {
        Layout.fillWidth: true
        Layout.preferredWidth: perfView.implicitWidth
        Layout.preferredHeight: perfView.implicitHeight

        DashPerf.Performance {
            id: perfView

            anchors.fill: parent
            compact: true
        }
    }
}
