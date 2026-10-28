import QtQuick
import Caelestia.Config

QtObject {
    property string currentName
    property bool hasCurrent
    property var dockModel: null
    property var tasksModel: null
    property string selectedClientAddress: ""
    property bool sidebarOpen: false
    readonly property bool isHorizontal: edge === "top" || edge === "bottom"
    property string edge: Config.bar.position
    property real inset: 0
    property int panelIndex: -1

    signal detachRequested(mode: string)

    function setOrigin(newEdge: string, newInset: real, newPanelIndex: int): void {
        edge = newEdge;
        inset = newInset;
        panelIndex = newPanelIndex;
    }
}
