import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var bar

    implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.2)
    implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.2)

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: root.implicitWidth + Tokens.padding.medium
        implicitHeight: root.implicitHeight + Tokens.padding.medium
        radius: Tokens.rounding.full
        onClicked: {
            const visibilities = Visibilities.getForActive();
            visibilities.utilities = !visibilities.utilities;
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: "tune"
            color: Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.medium
        }
    }
}
