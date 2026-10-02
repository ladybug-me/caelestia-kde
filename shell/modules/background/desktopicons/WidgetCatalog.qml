import QtQuick
import qs.utils

// The desktop widgets that can be added, with their sizes in grid cells.
QtObject {
    readonly property var types: [
        { type: "clock", name: qsTr("Clock & Weather"), icon: "partly_cloudy_day", size: { w: 4, h: 2 }, min: { w: 2, h: 2 }, max: { w: 6, h: 3 }, source: "widgets/ClockWidget.qml" },
        { type: "media", name: qsTr("Media"), icon: "music_note", size: { w: 4, h: 2 }, min: { w: 3, h: 2 }, max: { w: 6, h: 3 }, source: "widgets/MediaWidget.qml" },
        { type: "system", name: qsTr("System Monitor"), icon: "monitoring", size: { w: 3, h: 2 }, min: { w: 2, h: 2 }, max: { w: 6, h: 4 }, source: "widgets/SystemWidget.qml" },
        { type: "calendar", name: qsTr("Calendar"), icon: "calendar_month", size: { w: 3, h: 3 }, min: { w: 3, h: 3 }, max: { w: 5, h: 4 }, source: "widgets/CalendarWidget.qml" },
        { type: "note", name: qsTr("Note"), icon: "sticky_note_2", size: { w: 2, h: 2 }, min: { w: 2, h: 1 }, max: { w: 6, h: 6 }, source: "widgets/NoteWidget.qml", config: { text: "" } },
        { type: "folder", name: qsTr("Folder View"), icon: "folder_open", size: { w: 3, h: 3 }, min: { w: 2, h: 2 }, max: { w: 8, h: 6 }, source: "widgets/FolderWidget.qml", config: { path: Paths.home + "/Downloads" } }
    ]

    // Large folders are groups shown at more than one cell.
    readonly property var group: ({ type: "group", name: qsTr("Large Folder"), icon: "folder", size: { w: 3, h: 3 }, min: { w: 3, h: 3 }, max: { w: 8, h: 6 }, source: "BigFolder.qml" })

    function info(type: string): var {
        if (type === "group")
            return group;
        return types.find(t => t.type === type) ?? { type: "", name: "", icon: "widgets", size: { w: 1, h: 1 }, min: { w: 1, h: 1 }, max: { w: 1, h: 1 }, source: "" };
    }
}
