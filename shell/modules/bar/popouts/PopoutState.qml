import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    // True while the open popout was triggered from a top overlay panel,
    // so it drops downward instead of rising from the primary bar.
    property bool fromTopPanel: false
    // True while it was triggered from a floating top dock: same downward
    // placement, but starting below the dock card instead of the edge.
    property bool fromTopDock: false
    property var dockModel: null
    property var tasksModel: null
    property string selectedClientAddress: ""
    property bool sidebarOpen: false
    property bool isHorizontal: true

    signal detachRequested(mode: string)
}
