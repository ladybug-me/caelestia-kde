pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string pictures: Quickshell.env("XDG_PICTURES_DIR") || `${home}/Pictures`
    readonly property string videos: Quickshell.env("XDG_VIDEOS_DIR") || `${home}/Videos`

    readonly property string data: `${Quickshell.env("XDG_DATA_HOME") || `${home}/.local/share`}/caelestia`
    readonly property string state: `${Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`}/caelestia`
    readonly property string cache: `${Quickshell.env("XDG_CACHE_HOME") || `${home}/.cache`}/caelestia`
    readonly property string config: `${Quickshell.env("XDG_CONFIG_HOME") || `${home}/.config`}/caelestia`

    // XDG_RUNTIME_DIR is what a systemd session provides. Without one, a fixed name under
    // /tmp would be a path another local user could have created before this shell ran,
    // so the fallback is inside this user's own state directory and is claimed here.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || `${root.state}/run`

    function runtimeTemp(name: string): string {
        return `${runtimeDir}/caelestia-${name}`;
    }

    readonly property string imagecache: `${cache}/imagecache`

    readonly property string notifimagecache: `${imagecache}/notifs`

    readonly property string wallsdir: Quickshell.env("CAELESTIA_WALLPAPERS_DIR") || absolutePath(GlobalConfig.paths.wallpaperDir)

    readonly property string recsdir: Quickshell.env("CAELESTIA_RECORDINGS_DIR") || `${videos}/Recordings`

    readonly property string libdir: Quickshell.env("CAELESTIA_LIB_DIR") || "/usr/lib/caelestia"

    // Where the caelestia commands are installed: /usr/bin when a package owns
    // them, ~/.local/bin for a source install. Both autostart scripts export
    // CAELESTIA_BIN_DIR, and the fallback covers a shell started by hand.
    readonly property string binDir: Quickshell.env("CAELESTIA_BIN_DIR") || `${home}/.local/bin`

    function bin(name: string): string {
        return absolutePath(`${binDir}/${name}`);
    }

    function toLocalFile(path: url): string {
        path = Qt.resolvedUrl(path);
        return path.toString() ? CUtils.toLocalFile(path) : "";
    }

    function absolutePath(path: string): string {
        return toLocalFile(path.replace(/~|(\$({?)HOME(}?))+/, home).replace(/^root:/, Quickshell.shellDir + "/"));
    }

    function shortenHome(path: string): string {
        return path.replace(home, "~");
    }

    /// A path as a file dialog's `cwd` wants it: the home root, then one entry per
    /// segment below it. Anything outside home starts at the home root.
    function cwdSegments(path: string): var {
        if (!path || !home || !path.startsWith(home))
            return ["Home"];
        return ["Home", ...path.substring(home.length).split("/").filter(s => s.length > 0)];
    }

    // A session that did not come from systemd has no XDG_RUNTIME_DIR, and the fallback
    // above is then a directory nothing has created yet. Claiming it with a mode that
    // keeps other users out is what makes it safe to write sockets into.
    Process {
        running: !Quickshell.env("XDG_RUNTIME_DIR")
        command: ["install", "-d", "-m", "700", root.runtimeDir]
    }
}
