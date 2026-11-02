pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/// The engines the launcher can hand a query to, and the one KDE is configured to
/// use. Providers ship with kio as .desktop files and the choice is a single key in
/// kuriikwsfilterrc naming one of those files, which is also what KRunner and the
/// address bars of KIO clients read, so this service only touches that key.
Singleton {
    id: root

    /// What applies while the key is unset — KIO's shipped default.
    readonly property string defaultId: "duckduckgo"

    property list<var> providers: []
    property string configuredId: ""

    /// Set once an engine is picked here, so the read that starts with the shell
    /// cannot land afterwards and undo the choice.
    property bool _userPicked: false

    readonly property string currentId: root.configuredId || root.defaultId
    readonly property var currentProvider: root.providerFor(root.currentId)
    readonly property string currentName: root.currentProvider?.name ?? root.currentId

    function providerFor(id: string): var {
        for (let i = 0; i < root.providers.length; i++)
            if (root.providers[i].id === id)
                return root.providers[i];
        return null;
    }

    /// Provider templates hold the query as `\{@}`, which desktop files escape to
    /// `\\{@}`; every shipped provider is UTF-8, so the query is percent-encoded here.
    function searchUrl(query: string): string {
        const provider = root.currentProvider;
        if (!provider || !query)
            return "";
        return provider.query.replace(/\\*\{@\}/, encodeURIComponent(query));
    }

    function setProvider(id: string): void {
        if (!id || id === root.currentId)
            return;

        Quickshell.execDetached(["kwriteconfig6", "--file", "kuriikwsfilterrc", "--group", "General", "--key", "DefaultWebShortcut", id]);
        root._userPicked = true;
        root.configuredId = id;

        // Reload first: it can rebuild the runners, and the signal below is what tells
        // them, and the other KIO clients, to re-read the provider list.
        Search.reloadConfiguration();
        Quickshell.execDetached(["dbus-send", "--session", "--type=signal", "/", "org.kde.KUriFilterPlugin.configure"]);
    }

    function reload(): void {
        listProcess.running = true;
        readProcess.running = true;
    }

    /// One grep over both provider directories; grouping happens here rather than in
    /// shell, and the user directory comes second so it can override a shipped one.
    readonly property string listCommand: "grep -H -E '^(Name|Query|Hidden)=' /usr/share/kf6/searchproviders/*.desktop \"$HOME/.local/share/kio/searchproviders/\"*.desktop 2>/dev/null"

    function parseProviders(output: string): var {
        const byFile = {};
        const lines = output.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const colon = lines[i].indexOf(":");
            if (colon <= 0)
                continue;
            const path = lines[i].slice(0, colon);
            const body = lines[i].slice(colon + 1);
            const eq = body.indexOf("=");
            if (eq <= 0)
                continue;

            const field = body.slice(0, eq);
            const value = body.slice(eq + 1).trim();
            // The id has to be the file name: that is the value KIO resolves the
            // configured shortcut against, and it is not one of the typed aliases.
            if (!byFile[path])
                byFile[path] = {
                    id: path.slice(path.lastIndexOf("/") + 1, -".desktop".length),
                    name: "",
                    query: "",
                    hidden: false
                };
            const entry = byFile[path];
            if (field === "Name" && !entry.name)
                entry.name = value;
            else if (field === "Query" && !entry.query)
                entry.query = value;
            else if (field === "Hidden")
                entry.hidden = value === "true";
        }

        const byId = {};
        for (const path in byFile) {
            const entry = byFile[path];
            if (entry.name && entry.query && !entry.hidden)
                byId[entry.id] = entry;
        }

        const out = [];
        for (const id in byId)
            out.push(byId[id]);
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }

    Component.onCompleted: root.reload()

    Process {
        id: listProcess

        command: ["bash", "-c", root.listCommand]

        stdout: StdioCollector {
            onStreamFinished: root.providers = root.parseProviders(text)
        }
    }

    Process {
        id: readProcess

        command: ["kreadconfig6", "--file", "kuriikwsfilterrc", "--group", "General", "--key", "DefaultWebShortcut"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (!root._userPicked)
                    root.configuredId = text.trim();
            }
        }
    }
}
