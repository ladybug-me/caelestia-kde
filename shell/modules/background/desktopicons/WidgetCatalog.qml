import QtQuick
import qs.utils

// The desktop widgets that can be added, with their sizes in grid cells.
QtObject {
    readonly property var types: [
        { type: "clock", name: qsTr("Clock & Weather"), icon: "partly_cloudy_day", size: { w: 4, h: 2 }, min: { w: 2, h: 2 }, max: { w: 6, h: 3 }, source: "widgets/ClockWidget.qml" },
        { type: "desktopClock", name: qsTr("Desktop Clock"), icon: "schedule", size: { w: 4, h: 2 }, min: { w: 2, h: 2 }, max: { w: 8, h: 6 }, frameless: true, source: "widgets/DesktopClockWidget.qml" },
        { type: "media", name: qsTr("Media"), icon: "music_note", size: { w: 4, h: 2 }, min: { w: 3, h: 2 }, max: { w: 6, h: 3 }, source: "widgets/MediaWidget.qml" },
        { type: "shapes", name: qsTr("Media Shapes"), icon: "graphic_eq", size: { w: 3, h: 3 }, min: { w: 2, h: 2 }, max: { w: 6, h: 6 }, frameless: true, source: "widgets/ShapesWidget.qml" },
        { type: "lyrics", name: qsTr("Desktop Lyrics"), icon: "lyrics", size: { w: 4, h: 3 }, min: { w: 3, h: 2 }, max: { w: 8, h: 6 }, frameless: true, source: "widgets/LyricsWidget.qml" },
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

    function infoForGrid(type: string, maxCols: int, maxRows: int): var {
        const item = info(type);
        const limitW = maxCols > 0 ? maxCols : item.size.w;
        const limitH = maxRows > 0 ? maxRows : item.size.h;
        const w = Math.max(1, Math.min(item.size.w, limitW));
        const h = Math.max(1, Math.min(item.size.h, limitH));
        const minW = Math.max(1, Math.min(item.min.w, w));
        const minH = Math.max(1, Math.min(item.min.h, h));
        const maxW = Math.max(minW, Math.min(item.max.w, limitW));
        const maxH = Math.max(minH, Math.min(item.max.h, limitH));
        return Object.assign({}, item, {
            size: { w, h },
            min: { w: minW, h: minH },
            max: { w: maxW, h: maxH }
        });
    }
}
