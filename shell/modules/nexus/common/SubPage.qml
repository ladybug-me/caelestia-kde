pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    property int slot: -1
    property string key: ""
    property string label: ""
    property var keywords: []
    default property Component component
}
