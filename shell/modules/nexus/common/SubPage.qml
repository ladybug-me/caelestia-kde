pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    property int slot: -1
    property string key: ""
    default property Component component
}
