pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

// One file in ~/Desktop: its metadata, what to show for it and how to open it.
Scope {
    id: root

    required property string fileName
    required property string filePath
    required property bool fileIsDir
    required property string fileSuffix
    required property var fileModified
    required property var fileSize

    readonly property string key: DesktopLayout.fileKey(fileName)
    readonly property string path: filePath.replace("file://", "")
    readonly property string url: "file://" + path.split("/").map(encodeURIComponent).join("/")
    readonly property bool isDesktopFile: fileName.toLowerCase().endsWith(".desktop")
    readonly property string kind: fileIsDir ? "dir" : "file"
    // Rough type for "Sort by type": launchers together, then by extension.
    readonly property string typeName: isDesktopFile ? " application" : fileIsDir ? "" : fileSuffix.toLowerCase()

    property string desktopName: ""
    // The Name key the label was read from, e.g. "Name[zh_CN]".
    property string desktopNameKey: "Name"
    property bool desktopNameFound: false
    property string desktopIcon: ""
    property var desktopCategories: []

    readonly property string displayName: {
        if (!isDesktopFile)
            return fileName;
        if (desktopNameFound)
            return desktopName;
        return desktopEntry?.name || fileName.slice(0, -8);
    }

    readonly property DesktopEntry desktopEntry: {
        if (!isDesktopFile)
            return null;
        const cleanId = fileName.slice(0, -8);
        return DesktopEntries.applications.values.find(e => e.id === fileName || e.id === cleanId || e.id + ".desktop" === fileName)
            ?? DesktopEntries.heuristicLookup(cleanId)
            ?? null;
    }

    readonly property var categories: desktopCategories.length > 0 ? desktopCategories : (desktopEntry?.categories ?? [])

    readonly property string iconName: {
        if (fileIsDir)
            return "folder";
        if (isDesktopFile)
            return desktopIcon || desktopEntry?.icon || "application-x-executable";
        const ext = fileSuffix.toLowerCase();
        if (ext === "pdf")
            return "application-pdf";
        if (["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp"].includes(ext))
            return "image-x-generic";
        if (["mp4", "mkv", "webm", "avi", "mov"].includes(ext))
            return "video-x-generic";
        if (["zip", "tar", "gz", "rar", "7z"].includes(ext))
            return "package-x-generic";
        if (["mp3", "wav", "flac", "ogg"].includes(ext))
            return "audio-x-generic";
        if (["qml", "js", "html", "css", "py", "sh", "cpp", "c", "h", "json"].includes(ext))
            return "text-x-script";
        return "text-x-generic";
    }

    // Launcher icon name or absolute path, empty for plain files.
    readonly property string appIcon: isDesktopFile ? (desktopEntry?.icon || desktopIcon) : ""

    function iconSource(materialYou: bool): string {
        const setBase = Qt.resolvedUrl(Quickshell.shellDir + "/assets/icons/yet-another-monochrome-icon-set");
        if (appIcon !== "") {
            if (appIcon.startsWith("/"))
                return "file://" + appIcon;
            if (materialYou)
                return setBase + "/apps/scalable/" + appIcon + ".svg";
            return Quickshell.iconPath(appIcon, "application-x-executable");
        }
        if (materialYou) {
            if (fileIsDir)
                return setBase + "/places/scalable/folder.svg";
            return setBase + "/mimetypes/scalable/" + iconName + ".svg";
        }
        return "image://icon/" + iconName;
    }

    function fallbackIconSource(): string {
        if (appIcon !== "") {
            if (appIcon.startsWith("/"))
                return "file://" + appIcon;
            return Quickshell.iconPath(appIcon, "application-x-executable");
        }
        return "image://icon/" + iconName;
    }

    function launch(): void {
        // Run the launcher file itself: its name need not match an installed app id,
        // and xdg-open would open it in an editor instead.
        if (isDesktopFile)
            Launch.exec(["gio", "launch", path]);
        else
            Launch.exec(["xdg-open", path]);
    }

    // Opens files with this launcher, as when they are dropped onto it.
    function launchWith(paths: var): void {
        if (isDesktopFile)
            Launch.exec(["gio", "launch", path, ...paths]);
    }

    function reloadDesktopFile(): void {
        desktopFile.reload();
    }

    FileView {
        id: desktopFile

        path: root.isDesktopFile ? root.path : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            // Prefer Name[lang_COUNTRY], then Name[lang], then Name, as the spec says.
            const locale = Qt.locale().name;
            const nameKeys = [`Name[${locale}]`, `Name[${locale.split("_")[0]}]`, "Name"];
            const values = {};
            let inDesktopEntry = false;
            for (const raw of text().split("\n")) {
                const line = raw.trim();
                if (line.startsWith("[")) {
                    inDesktopEntry = line === "[Desktop Entry]";
                    continue;
                }
                const eq = line.indexOf("=");
                if (!inDesktopEntry || eq < 0)
                    continue;
                const key = line.substring(0, eq).trim();
                if (!(key in values))
                    values[key] = line.substring(eq + 1).trim();
            }
            const nameKey = nameKeys.find(k => values[k]);
            root.desktopNameFound = !!nameKey;
            if (nameKey) {
                root.desktopName = values[nameKey];
                root.desktopNameKey = nameKey;
            }
            root.desktopIcon = values["Icon"] ?? "";
            root.desktopCategories = (values["Categories"] ?? "").split(";").filter(c => c.length > 0);
        }
    }
}
