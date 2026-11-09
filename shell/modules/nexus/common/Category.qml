pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    property int categoryIdx: -1
    property string key: ""
    property string label: ""
    property string icon: ""
    property string description: ""
    property string defaultPage: ""
    default property list<Page> pages
}
