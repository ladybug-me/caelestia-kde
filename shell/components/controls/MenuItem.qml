pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    property string text: ""
    property string icon
    property string trailingIcon
    property string activeIcon: icon
    property string activeText: text
    property bool visible: true
    property var submenu: []
    property var value

    signal clicked
}
