pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    property int slot: -1
    property string key: ""
    property string label: ""
    property string icon: ""
    property string status: ""
    property string description: ""
    property string section: ""
    property bool enabled: true
    property var keywords: []
    default property Component component
    property list<SubPage> subPages
}
