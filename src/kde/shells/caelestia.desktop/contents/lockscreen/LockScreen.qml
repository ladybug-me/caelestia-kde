
import QtQuick
import Caelestia.Services
import M3Shapes

Item {
    id: root

    property bool locked: true
    property bool viewVisible: false
    property string notification

    signal clearPassword()
    signal notificationRepeated()

    onViewVisibleChanged: {
        if (viewVisible && lockScreenUi && typeof lockScreenUi.ensureAuthenticating === "function") {
            lockScreenUi.ensureAuthenticating();
        }
    }

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true
    implicitWidth: 800
    implicitHeight: 600

    LockScreenUi {
        id: lockScreenUi

        anchors.fill: parent
    }
}
