import QtQuick
import Quickshell
import Quickshell.Hyprland as Hypr
import Caelestia.Services as Caelestia

Loader {
    id: root

    property string name: ""
    property string description: ""
    property var key
    property bool enabled: true

    signal pressed()
    signal released()

    active: root.enabled

    sourceComponent: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? hyprShortcut : kdeShortcut

    Component {
        id: hyprShortcut

        Hypr.GlobalShortcut {
            appid: "caelestia"
            name: root.name
            description: root.description
            onPressed: root.pressed()
            onReleased: root.released()
        }
    }

    Component {
        id: kdeShortcut

        Caelestia.GlobalShortcut {
            name: root.name
            description: root.description
            onActivated: {
                root.pressed()
                root.released()
            }

            Binding on key {
                when: root.key !== undefined
                value: root.key ?? ""
            }
        }
    }
}
