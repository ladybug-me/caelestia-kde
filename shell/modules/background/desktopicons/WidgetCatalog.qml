import QtQuick
import Caelestia.Config
import qs.utils

// The desktop widgets that can be added, with their sizes in grid cells and the
// settings each one offers. The settings are data rather than QML: the inspector
// builds its form from them, so a widget gains a control by describing it here.
QtObject {
    id: root

    readonly property var types: [
        {
            type: "clock",
            name: qsTr("Clock & Weather"),
            icon: "partly_cloudy_day",
            size: { w: 4, h: 2 },
            min: { w: 2, h: 2 },
            max: { w: 6, h: 3 },
            source: "widgets/ClockWidget.qml",
            settings: [
                { key: "showWeather", type: "toggle", label: qsTr("Show weather"), default: true },
                { key: "showHourly", type: "toggle", label: qsTr("Show hourly forecast"), default: true, description: qsTr("Only when the widget is wide enough") }
            ]
        },
        {
            type: "weather",
            name: qsTr("Weather"),
            icon: "cloud",
            size: { w: 3, h: 2 },
            min: { w: 2, h: 2 },
            max: { w: 6, h: 4 },
            source: "widgets/WeatherWidget.qml",
            settings: [
                { key: "showForecast", type: "toggle", label: qsTr("Show forecast"), default: true, description: qsTr("Daily highs and lows below the current weather") },
                { key: "forecastDays", type: "slider", label: qsTr("Forecast days"), default: 3, min: 1, max: 6, step: 1, integer: true }
            ]
        },
        { type: "desktopClock", name: qsTr("Desktop Clock"), icon: "schedule", size: { w: 4, h: 2 }, min: { w: 2, h: 2 }, max: { w: 8, h: 6 }, frameless: true, source: "widgets/DesktopClockWidget.qml" },
        {
            type: "media",
            name: qsTr("Media"),
            icon: "music_note",
            size: { w: 4, h: 2 },
            min: { w: 3, h: 2 },
            max: { w: 6, h: 3 },
            source: "widgets/MediaWidget.qml",
            settings: [
                { key: "layout", type: "select", label: qsTr("Layout"), default: "horizontal", options: [
                    { value: "horizontal", label: qsTr("Artwork beside") },
                    { value: "vertical", label: qsTr("Artwork above") }
                ] },
                { key: "albumArtBackground", type: "toggle", label: qsTr("Artwork background"), default: false, description: qsTr("Blur the current artwork behind the player") },
                { key: "hideWhenNoMedia", type: "toggle", label: qsTr("Hide when idle"), default: false, description: qsTr("Hide the widget while nothing is playing") }
            ]
        },
        { type: "shapes", name: qsTr("Media Shapes"), icon: "graphic_eq", size: { w: 3, h: 3 }, min: { w: 2, h: 2 }, max: { w: 6, h: 6 }, frameless: true, source: "widgets/ShapesWidget.qml" },
        { type: "lyrics", name: qsTr("Desktop Lyrics"), icon: "lyrics", size: { w: 4, h: 3 }, min: { w: 3, h: 2 }, max: { w: 8, h: 6 }, frameless: true, source: "widgets/LyricsWidget.qml" },
        { type: "system", name: qsTr("System Monitor"), icon: "monitoring", size: { w: 3, h: 2 }, min: { w: 2, h: 2 }, max: { w: 6, h: 4 }, source: "widgets/SystemWidget.qml" },
        {
            type: "calendar",
            name: qsTr("Calendar"),
            icon: "calendar_month",
            size: { w: 3, h: 3 },
            min: { w: 3, h: 3 },
            max: { w: 5, h: 4 },
            source: "widgets/CalendarWidget.qml",
            settings: [
                { key: "showEvents", type: "toggle", label: qsTr("Show agenda"), default: true, description: qsTr("List the picked day's events next to the month") }
            ]
        },
        { type: "note", name: qsTr("Note"), icon: "sticky_note_2", size: { w: 2, h: 2 }, min: { w: 2, h: 1 }, max: { w: 6, h: 6 }, source: "widgets/NoteWidget.qml", config: { text: "" } },
        {
            type: "volume",
            name: qsTr("Volume"),
            icon: "volume_up",
            size: { w: 2, h: 2 },
            min: { w: 2, h: 2 },
            max: { w: 4, h: 3 },
            source: "widgets/VolumeWidget.qml",
            settings: [
                { key: "device", type: "select", label: qsTr("Device"), default: "output", options: [
                    { value: "output", label: qsTr("Output") },
                    { value: "input", label: qsTr("Microphone") }
                ] },
                { key: "showDevice", type: "toggle", label: qsTr("Show device name"), default: true }
            ]
        },
        {
            type: "button",
            name: qsTr("Button"),
            icon: "smart_button",
            size: { w: 2, h: 1 },
            min: { w: 1, h: 1 },
            max: { w: 6, h: 2 },
            source: "widgets/ButtonWidget.qml",
            config: { glyph: "terminal", label: qsTr("Terminal"), command: "terminal" },
            settings: [
                { key: "glyph", type: "text", label: qsTr("Icon"), default: "terminal", placeholder: qsTr("Material icon name") },
                { key: "label", type: "text", label: qsTr("Label"), default: qsTr("Terminal") },
                { key: "command", type: "text", label: qsTr("Command"), default: "terminal", placeholder: qsTr("Run on click") }
            ]
        },
        {
            type: "sticker",
            name: qsTr("Sticker"),
            icon: "image",
            size: { w: 2, h: 2 },
            min: { w: 1, h: 1 },
            max: { w: 8, h: 8 },
            frameless: true,
            source: "widgets/StickerWidget.qml",
            config: { path: "" },
            settings: [
                { key: "path", type: "path", mode: "file", label: qsTr("Image"), default: "", placeholder: qsTr("PNG, JPEG, WebP, SVG or GIF") },
                { key: "opacity", type: "slider", label: qsTr("Image opacity"), default: 1, min: 0.1, max: 1, step: 0.05 }
            ]
        },
        { type: "folder", name: qsTr("Folder View"), icon: "folder_open", size: { w: 3, h: 3 }, min: { w: 2, h: 2 }, max: { w: 8, h: 6 }, source: "widgets/FolderWidget.qml", config: { path: Paths.home + "/Downloads" } }
    ]

    // Large folders are groups shown at more than one cell.
    readonly property var group: ({ type: "group", name: qsTr("Large Folder"), icon: "folder", size: { w: 3, h: 3 }, min: { w: 3, h: 3 }, max: { w: 8, h: 6 }, source: "BigFolder.qml" })

    // The card every widget can draw, and the two knobs that shape it. Kept apart
    // from `types` because every type offers the same three controls.
    readonly property var appearance: [
        { key: "background", type: "toggle", label: qsTr("Background"), default: true, description: qsTr("Draw the card behind the widget's content") },
        { key: "backgroundOpacity", type: "slider", label: qsTr("Background opacity"), default: defaultBackgroundOpacity, min: 0.05, max: 1, step: 0.05 },
        { key: "backgroundRadius", type: "slider", label: qsTr("Corner radius"), default: defaultBackgroundRadius, min: 0, max: 36, step: 1, integer: true }
    ]

    // Pitch black is meant to disappear into the wallpaper, so its card is denser.
    readonly property real defaultBackgroundOpacity: GlobalConfig.appearance.pitchBlack ? 0.7 : 0.4
    readonly property real defaultBackgroundRadius: Tokens.rounding.extraLarge

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

    // What this type lets you change: the card first, then the type's own controls.
    function settingsFor(type: string): var {
        const rows = [];
        for (const row of root.appearance) {
            // A widget that never had a card (lyrics, shapes, stickers) starts without one.
            if (row.key === "background")
                rows.push(Object.assign({}, row, { default: info(type).frameless !== true }));
            else
                rows.push(row);
        }
        for (const row of (info(type).settings ?? []))
            rows.push(row);
        return rows;
    }

    // The config a widget of this type holds when nothing has been changed, so that
    // "Reset" has something to write and every control has a value to show.
    function defaultsFor(type: string): var {
        const out = Object.assign({}, info(type).config ?? {});
        for (const row of settingsFor(type))
            if (row.default !== undefined)
                out[row.key] = row.default;
        return out;
    }
}
