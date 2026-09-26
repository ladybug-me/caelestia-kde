pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property string fallback: Quickshell.shellPath("assets/wallpapers/Minimal-Paper.png")

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear
    property var videoThumbs: ({})
    property var videoThumbsPending: ({})

    property string currentMediaFilter: "All"

    property var filteredList: {
        const res = wallpapers.entries || [];
        if (currentMediaFilter === "Image") {
            return res.filter(w => !Images.isVideo(w.relativePath) && !Images.isAnimated(w.relativePath));
        } else if (currentMediaFilter === "Video") {
            return res.filter(w => Images.isVideo(w.relativePath));
        } else if (currentMediaFilter === "Animated") {
            return res.filter(w => Images.isAnimated(w.relativePath));
        }
        return res;
    }

    readonly property var categories: {
        let dummy = root.list;
        const baseDir = Paths.wallsdir;
        let cats = [];
        for (let i = 0; i < root.list.length; i++) {
            let p = root.list[i].parentDir;
            if (p !== baseDir) {
                let cat = p.slice(baseDir.length + 1);
                if (cat.includes("/")) cat = cat.slice(0, cat.indexOf("/"));
                if (!cats.includes(cat)) cats.push(cat);
            }
        }
        return ["Main"].concat(cats.sort());
    }

    readonly property var grouped: {
        let dummy = root.list;
        const baseDir = Paths.wallsdir;
        let grp = { "Main": [] };
        for (let i = 0; i < root.list.length; i++) {
            let w = root.list[i];
            let p = w.parentDir;
            if (p === baseDir) {
                grp["Main"].push(w);
            } else {
                let cat = p.slice(baseDir.length + 1);
                if (cat.includes("/")) cat = cat.slice(0, cat.indexOf("/"));
                if (!grp[cat]) grp[cat] = [];
                grp[cat].push(w);
            }
        }
        return grp;
    }

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        // `caelestia wallpaper` takes a still image, so a live or video
        // wallpaper is put in place through the same path as any other
        // (setWallpaper); pick the random one here rather than passing -r.
        if (!root.list || root.list.length === 0) return;
        let idx = Math.floor(Math.random() * root.list.length);
        if (root.list.length > 1 && root.list[idx].path === actualCurrent)
            idx = (idx + 1) % root.list.length;
        setWallpaper(root.list[idx].path);
    }

    function setNextSequential(): void {
        if (!root.list || root.list.length === 0) return;
        let idx = -1;
        for (let i = 0; i < root.list.length; i++) {
            if (root.list[i].path === actualCurrent) {
                idx = i;
                break;
            }
        }
        idx = (idx + 1) % root.list.length;
        setWallpaper(root.list[idx].path);
    }

    function next(): void {
        if (GlobalConfig.background.slideshowRandom) {
            setRandom();
        } else {
            setNextSequential();
        }
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        if (Images.isVideo(path)) {
            const thumb = thumbFor(path);
            if (thumb !== "") {
                const script = 'caelestia wallpaper -f "$1" ' + Colours.smartArg.join(" ") + '; printf "%s" "$2" > "$3"';
                Quickshell.execDetached(["sh", "-c", script, "--", thumb, path, root.currentNamePath]);
                syncPlasmaWallpaper(thumb);
            } else {
                Quickshell.execDetached(["sh", "-c", 'printf "%s" > "$1"', "--", path, root.currentNamePath]);
                // Still frame not ready yet — onVideoThumb() syncs Plasma once it is.
            }
        } else {
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...Colours.smartArg]);
            syncPlasmaWallpaper(path);
        }
    }

    // Mirrors the wallpaper onto Plasma's own desktop background so it doesn't
    // stay stale (e.g. showing the deploy-time default) whenever the shell
    // isn't running to keep it in sync itself, such as after a crash/exit.
    function syncPlasmaWallpaper(imagePath: string): void {
        if (!imagePath)
            return;
        const script = 'var allDesktops = desktops();' +
            'for (var i = 0; i < allDesktops.length; i++) {' +
            '    var d = allDesktops[i];' +
            '    d.wallpaperPlugin = "org.kde.image";' +
            '    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];' +
            '    d.writeConfig("Image", "file://" + ' + JSON.stringify(imagePath) + ');' +
            '}';
        Quickshell.execDetached(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script]);

        // Keep KDE's own lock screen wallpaper on the same image unless the user
        // opted out of syncing the two. Read the global singleton directly: the
        // attached `Config` is per-screen aware and is not meant to be used from
        // a singleton service like this one.
        if (GlobalConfig.lock.syncWallpaper)
            Quickshell.execDetached(["kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.image", "--group", "General", "--key", "Image", "file://" + imagePath]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    function getThumbnailPath(path: string): string {
        if (Images.isVideo(path)) {
            return `${Paths.cache}/wallpapers/${CUtils.sha256(path)}/first_frame.png`;
        }
        return path;
    }

    function thumbFor(path: string): string {
        const p = String(path || "").replace(/^file:\/\//, "");
        if (p === "" || !Images.isVideo(p))
            return p;
        if (root.videoThumbs[p])
            return root.videoThumbs[p];
        requestVideoThumb(p);
        return "";
    }

    function requestVideoThumb(path: string): void {
        if (root.videoThumbsPending[path] || root.videoThumbs[path])
            return;
        const pending = root.videoThumbsPending;
        pending[path] = true;
        root.videoThumbsPending = pending;

        const out = getThumbnailPath(path);
        const script = 'out="$1"; src="$2"; [ -s "$out" ] || { mkdir -p "$(dirname "$out")"; ' +
                       'ffmpeg -y -loglevel error -i "$src" -vf "thumbnail,scale=640:-1" -frames:v 1 "$out" >/dev/null 2>&1; }; ' +
                       '[ -s "$out" ] && printf %s "$out"';
        const qml = 'import QtQuick\nimport Quickshell.Io\n' +
            'Process {\n' +
            '    id: p\n' +
            '    command: ' + JSON.stringify(["sh", "-c", script, "--", out, path]) + '\n' +
            '    stdout: StdioCollector { onStreamFinished: root.onVideoThumb(' + JSON.stringify(path) + ', (text || "").trim(), p); }\n' +
            '    onExited: code => { if (code !== 0) p.destroy(); }\n' +
            '}';
        try {
            const o = Qt.createQmlObject(qml, root, "videoThumbProc");
            o.running = true;
        } catch (e) {
            Logger.log("[wallpapers] video thumbnail error: " + e.message);
        }
    }

    function onVideoThumb(path: string, out: string, proc: var): void {
        if (out !== "") {
            const m = root.videoThumbs;
            m[path] = out;
            root.videoThumbs = Object.assign({}, m);   // a copy, so bindings re-run
            if (path === root.actualCurrent) {
                const script = 'caelestia wallpaper -f "$1" ' + Colours.smartArg.join(" ") + '; printf "%s" "$2" > "$3"';
                Quickshell.execDetached(["sh", "-c", script, "--", out, path, root.currentNamePath]);
                syncPlasmaWallpaper(out);
            }
        }
        const pending = root.videoThumbsPending;
        delete pending[path];
        root.videoThumbsPending = pending;
        if (proc)
            proc.destroy();
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: filteredList
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...Colours.smartArg]);
            }
            if (Images.isVideo(root.actualCurrent) && wall === root.getThumbnailPath(root.actualCurrent)) {
                return;
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;
            // Bring the KDE lock screen in line with the shell whenever the
            // persisted wallpaper is (re)loaded, e.g. on startup. Videos are
            // skipped: the lock screen falls back to an image, and the video
            // path has no still to show until onVideoThumb() provides one.
            if (!Images.isVideo(wall))
                syncPlasmaWallpaper(wall);
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...Colours.smartArg]);
            syncPlasmaWallpaper(root.fallback);
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Files
        nameFilters: Images.validImageExtensions.concat(Images.validVideoExtensions).map(e => `*.${e}`)
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...Colours.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
