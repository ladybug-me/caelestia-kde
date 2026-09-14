import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight

    StateLayer {
        // Cursed workaround to make the height larger than the parent
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        Accessible.name: qsTr("Show desktop")
        Accessible.role: Accessible.Button
        Accessible.description: qsTr("Minimize all windows to show the desktop")
        onClicked: Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "Show Desktop"])
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: Centering.pixelAlign(parent.width, width)

        text: "keyboard_double_arrow_down"
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()

        // Derived from KWin so the arrow stays in sync with the real "show
        // desktop" state: toggling it any other way still flips the arrow, and
        // a failed invocation never leaves it pointing the wrong way.
        rotation: (Kwin.showingDesktop) ? 180 : 0

        Behavior on rotation {
            Anim { type: Anim.FastSpatial }
        }
    }
}
