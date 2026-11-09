pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    property int categoryIdx: -1
    property string key: ""
    property string label: ""
    property string icon: ""
    property string description: ""
    property int defaultSlot: 0
    default property list<Page> pages
}
