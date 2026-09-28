import QtQuick
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
        // KWin's showDesktop() takes the state to end up in; the kglobalaccel
        // shortcut this used to shell out to is a toggle whose result cannot be
        // read back, so a second click could leave the desktop showing.
        onClicked: Kwin.setShowingDesktop(!Kwin.showingDesktop)
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: Centering.pixelAlign(parent.width, width)

        text: "keyboard_double_arrow_down"
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()

        rotation: (Kwin.showingDesktop) ? 180 : 0

        Behavior on rotation {
            Anim { type: Anim.FastSpatial }
        }
    }
}
