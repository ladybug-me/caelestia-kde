pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    property string key: ""
    property string label: ""
    property string icon: ""
    property string status: ""
    property string description: ""
    property string section: ""
    property bool enabled: true
    property var keywords: []
    property Component component
    default property list<SubPage> subPages
}
