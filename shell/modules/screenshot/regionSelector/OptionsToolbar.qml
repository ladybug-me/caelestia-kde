import ".."
import "../../../components/controls"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.utils

Toolbar {
    id: root

    property var action
    property var selectionMode
    property bool showWindowOutlines: false

    signal dismiss()

    IconButton {
        id: windowSelectorBtn

        Layout.alignment: Qt.AlignVCenter
        icon: "desktop_windows"
        isToggle: true
        type: IconButton.Text
        padding: 4
        implicitWidth: 32
        implicitHeight: 32
        checked: root.showWindowOutlines
        onClicked: {
            root.showWindowOutlines = internalChecked;
        }

        Tooltip {
            target: windowSelectorBtn
            text: qsTr("Window Selector")
        }
    }

    ToolbarTabBar {
        id: tabBar

        tabButtonList: [
            {"icon": "content_cut", "name": qsTr("Screenshot")},
            {"icon": "image_search", "name": qsTr("Google Lens")},
            {"icon": "text_fields", "name": qsTr("Text Recognition")}
        ]
        currentIndex: root.action === ScreenshotAction.SnipAction.Search ? 1 : (root.action === ScreenshotAction.SnipAction.CharRecognition ? 2 : 0)
        onTabClicked: index => {
            let newAction;
            if (index === 0) newAction = ScreenshotAction.SnipAction.Copy;
            else if (index === 1) newAction = ScreenshotAction.SnipAction.Search;
            else if (index === 2) newAction = ScreenshotAction.SnipAction.CharRecognition;
            else return;

            if (root.action !== newAction) {
                root.action = newAction;
                root.selectionMode = RegionSelection.SelectionMode.RectCorners;
            }
        }
    }
}
