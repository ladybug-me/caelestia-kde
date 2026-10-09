import QtQuick
import Caelestia.Services as Caelestia

Loader {
    id: root

    property string name: ""
    property string description: ""
    property string key: ""
    property bool enabled: true

    signal pressed()
    signal released()

    active: root.enabled

    sourceComponent: kdeShortcut

    Component {
        id: kdeShortcut

        Caelestia.GlobalShortcut {
            name: root.name
            key: root.key
            description: root.description
            onActivated: {
                root.pressed()
                root.released()
            }
        }
    }
}
