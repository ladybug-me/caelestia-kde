pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services
import qs.utils

StyledRect {
    id: root

    property bool active: false
    property bool loading: false
    property bool interactive: true
    property real iconScale: 1.0

    signal clicked()

    implicitWidth: implicitHeight
    implicitHeight: icon.implicitHeight + Tokens.padding.extraSmall * root.iconScale

    radius: Tokens.rounding.full * root.iconScale
    color: Qt.alpha(Colours.palette.m3primary, root.active ? 1 : 0)

    CircularIndicator {
        anchors.fill: parent
        running: root.loading
    }

    StateLayer {
        color: root.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
        disabled: root.loading || !root.interactive
        onClicked: root.clicked()
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        animate: true
        text: root.active ? "link_off" : "link"
        color: root.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
        fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.iconScale

        opacity: root.loading ? 0 : 1

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
