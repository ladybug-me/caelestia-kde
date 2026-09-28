import Quickshell

PersistentProperties {
    required property ShellScreen modelData

    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar

    property int dashboardTab
    property date dashboardDate: new Date()

    reloadableId: `screenState-${modelData.name}`
}
