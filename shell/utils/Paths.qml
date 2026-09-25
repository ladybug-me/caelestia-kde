pragma Singleton

import QtQuick
import Quickshell
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
    
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || `/tmp/caelestia-${Quickshell.env("USER")}`
    
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

    // Join a host and port into an origin, for servers the user points the shell
    // at by hand. A host that already carries a port keeps it, so a pasted
    // "host:port" is not given a second one.
    function hostPort(host: string, port: int): string {
        const h = (host || "").trim();
        if (h === "")
            return `localhost:${port}`;
        if (h.startsWith("["))
            // Bracketed IPv6 literal. The port goes inside the brackets, which is
            // the only form a URL parser accepts; an existing port is left alone.
            return h.endsWith("]") ? `${h}:${port}` : h;
        if (h.indexOf(":") !== -1)
            // Already a host:port, or a bare IPv6 literal the user did not bracket.
            return h;
        return `${h}:${port}`;
    }

    // Build the base URL of an OpenAI-compatible server from the host and port a
    // user typed. Deliberately forgiving, because people paste whatever address
    // they have to hand: a bare host, "host:port", a full URL, or a URL that
    // already ends in /v1 all resolve to the same endpoint instead of producing a
    // broken request to something like http://host:8080/v1/v1.
    //
    // Returns the /v1 base; callers append /models or /chat/completions.
    function openaiCompatBase(host: string, port: int): string {
        // 8080 is llama-server's own default. Coerced here rather than at the call
        // site so every caller gets the same fallback for a blank or unparseable
        // port instead of building a URL ending in ":undefined".
        const p = Math.trunc(Number(port)) || 8080;
        let h = (host || "").trim();
        let scheme = "http://";

        // A pasted scheme is honoured: a server reached over https must not be
        // silently downgraded to http.
        if (h.startsWith("https://")) {
            scheme = "https://";
            h = h.substring(8);
        } else if (h.startsWith("http://")) {
            h = h.substring(7);
        }

        if (h === "")
            h = "localhost";

        // Drop a trailing /v1 (with or without a slash) and any trailing slash, so
        // the /v1 added below is not doubled. Only one is stripped: a path that
        // legitimately ends in /v1 twice is already broken input.
        h = h.replace(/\/+$/, "");
        h = h.replace(/\/v1$/, "");
        h = h.replace(/\/+$/, "");

        if (h === "")
            h = "localhost";

        return scheme + root.hostPort(h, p) + "/v1";
    }
}
