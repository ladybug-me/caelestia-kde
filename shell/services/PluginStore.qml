pragma Singleton

import qs.services.api
import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

Item {
    id: storeRoot

    // GitHub org the plugin repositories are cloned from. Forks point this at
    // their own org with CAELESTIA_REPO_OWNER so plugin installs come from the
    // fork instead of upstream. The store index below stays pinned to the
    // canonical upstream repository (it is the content source).
    readonly property string repoOwner: Qt.getenv("CAELESTIA_REPO_OWNER") || "ladybug-me"
    readonly property string pluginsRepoUrl: "https://github.com/" + repoOwner + "/caelestia-kde-plugins.git"
    readonly property string storeIndexBaseUrl: "https://raw.githubusercontent.com/ladybug-me/caelestia-kde-plugins"

    property bool loading: false
    property bool error: false
    property string errorMessage: ""

    property bool installing: false
    property string installProgress: ""

    property bool restartRequired: false

    // Predicted installed state — seeded once from disk scan on startup,
    // then mutated purely by user actions (no re-scanning at runtime).
    property var installedPluginIds: []
    property bool baselineLoaded: false

    // Raw index from the server
    property var indexData: null
    property ListModel storePlugins: ListModel {}

    // Store index fields are remote-controlled data that ends up in shell
    // commands and filesystem paths, so every field must pass this allow-list
    // before it is used anywhere. It admits plain plugin identifiers and repo
    // paths and rejects everything that could break out of quoting or traverse
    // directories ($ ` ; & | < > " ' whitespace, control characters, "..",
    // absolute paths).
    readonly property var safeFieldRegex: /^[A-Za-z0-9._\/-]{1,128}$/

    signal indexFetched()
    signal installedStateChanged()

    function isValidStoreField(field) {
        return typeof field === "string"
            && safeFieldRegex.test(field)
            && field.indexOf("..") === -1
            && field.charAt(0) !== "/";
    }

    // Removal never goes through a shell (plain argv), so a display name with
    // spaces stays valid; the guards that matter there are directory traversal
    // and absolute paths, since the id becomes an `rm -rf` target.
    function isRemovablePluginId(field) {
        return typeof field === "string"
            && field.length > 0
            && field.length <= 128
            && field.indexOf("..") === -1
            && field.charAt(0) !== "/"
            && field.indexOf("\n") === -1;
    }

    function fetchIndex(branch) {
        let fetchBranch = branch || "main";
        loading = true;
        error = false;
        errorMessage = "";

        // Seed installed IDs from disk baseline if not done yet
        // (handles the race condition where fetchIndex resolves before PluginLoader's pluginsReloaded)
        if (!baselineLoaded && CaelestiaApi.plugins.available.count > 0) {
            baselineLoaded = true;
            let ids = [];
            let av = CaelestiaApi.plugins.available;
            for (let i = 0; i < av.count; i++)
                ids.push(av.get(i).id);
            installedPluginIds = ids;
            console.log("PluginStore: baseline seeded in fetchIndex:", JSON.stringify(ids));
        }

        fetchProc.command = ["curl", "-sfL", storeIndexBaseUrl + "/" + fetchBranch + "/index.json"];
        fetchProc.running = true;
    }

    function installPlugin(id, repoPath, branch, restart) {
        if (!id) return;

        let installBranch = branch || "main";

        let actualRepoPath = repoPath || ("plugins/" + id);

        // id, repoPath and branch come straight from the remote store index, so
        // they are attacker-controlled. Validate the values that will actually
        // be used before anything touches the shell or the disk; on failure
        // surface a graceful error instead of silently doing nothing.
        if (!isValidStoreField(id) || !isValidStoreField(actualRepoPath) || !isValidStoreField(installBranch)) {
            error = true;
            installing = false;
            installProgress = "";
            errorMessage = qsTr("Rejected plugin \"%1\": the store entry contains an unsafe id, path or branch").arg(id);
            console.warn("PluginStore: rejected unsafe store entry", JSON.stringify({
                id: id,
                repoPath: actualRepoPath,
                branch: installBranch
            }));
            return;
        }

        installing = true;
        installProgress = qsTr("Cloning plugin '%1'...").arg(id);

        let targetDir = (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/caelestia/plugins/" + id;

        // The script is fully static: every remote-controlled value rides as an
        // argv element after "--" ($1 id, $2 repo path, $3 branch, $4 target
        // dir, $5 repo url) and is only ever expanded inside double quotes, so
        // no store entry can inject shell syntax.
        let script = `set -euo pipefail
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cd "$TMP_DIR"
git init -q
git remote add origin "$5"
git config core.sparseCheckout true
echo "$2/*" >> .git/info/sparse-checkout
git fetch -q --depth 1 --filter=blob:none origin "$3"
git reset --hard -q "origin/$3"
mkdir -p "$(dirname "$4")"
rm -rf "$4"
mv "$2" "$4"
echo "DONE"`;

        installProc.pendingId = id;
        installProc.pendingTargetDir = targetDir;
        installProc.pendingRestart = (restart === "true" || restart === true);
        installProc.command = ["bash", "-c", script, "--", id, actualRepoPath, installBranch, targetDir, pluginsRepoUrl];
        installProc.running = true;
    }

    function removePlugin(id) {
        // The id ends up in an `rm -rf` target, so it must be a safe path
        // component (no traversal, no absolute path).
        if (!isRemovablePluginId(id)) {
            error = true;
            errorMessage = qsTr("Refused to remove plugin \"%1\": unsafe id").arg(id);
            console.warn("PluginStore: refusing to remove plugin with unsafe id:", id);
            return;
        }
        let targetDir = (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/caelestia/plugins/" + id;
        removeProc.pendingId = id;
        // Determine whether this plugin requires a restart when removed.
        let requiresRestart = false;
        for (let i = 0; i < CaelestiaApi.plugins.available.count; i++) {
            let p = CaelestiaApi.plugins.available.get(i);
            if ((p.id || p.name) === id) {
                requiresRestart = (p.restart === "true" || p.restart === true);
                break;
            }
        }
        removeProc.pendingRestart = requiresRestart;
        removeProc.command = ["rm", "-rf", targetDir];
        removeProc.running = true;
    }

    Connections {
        target: PluginLoader

        function onPluginsReloaded() {
            // Only seed once from the startup scan
            if (storeRoot.baselineLoaded)
                return;
            storeRoot.baselineLoaded = true;
            let ids = [];
            let av = CaelestiaApi.plugins.available;
            for (let i = 0; i < av.count; i++)
                ids.push(av.get(i).id);
            storeRoot.installedPluginIds = ids;
            console.log("PluginStore: baseline loaded, installed:", JSON.stringify(ids));
        }
    }

    // ── 1. Fetch store index ──────────────────────────────────────────────────

    Process {
        id: fetchProc

        stdout: StdioCollector { id: fetchOut }
        stderr: StdioCollector { id: fetchErr }

        onExited: (code) => {
            storeRoot.loading = false;
            if (code !== 0) {
                storeRoot.error = true;
                storeRoot.errorMessage = "Failed to fetch plugins index (curl exit " + code + "): " + fetchErr.text;
            } else {
                try {
                    storeRoot.indexData = JSON.parse(fetchOut.text);
                    storeRoot.storePlugins.clear();
                    let plugins = storeRoot.indexData.plugins || [];
                    for (let i = 0; i < plugins.length; i++) {
                        let p = plugins[i];
                        // Rename 'id' to 'pluginId' to avoid clash with QML's reserved 'id' keyword
                        // in ComponentBehavior:Bound delegates
                        p.pluginId = p.id;
                        p.path = p.path || ("plugins/" + p.id);
                        p.mediaurl = p.mediaurl || "";
                        p.authorName = p.author ? (p.author.name || "") : "";
                        let aUrl = p.author ? (p.author.url || "") : "";
                        p.icon = p.icon || "extension";
                        p.restart = (p.restart === "true" || p.restart === true);
                        storeRoot.storePlugins.append(p);
                    }
                    storeRoot.indexFetched();
                } catch (e) {
                    storeRoot.error = true;
                    storeRoot.errorMessage = "Failed to parse index JSON: " + e;
                }
            }
        }
    }

    // ── 2. Install a plugin ───────────────────────────────────────────────────

    Process {
        id: installProc

        property string pendingId: ""
        property string pendingTargetDir: ""
        property bool pendingRestart: false

        stdout: StdioCollector { id: installOut }
        stderr: StdioCollector { id: installErr }

        onExited: (code) => {
            storeRoot.installing = false;
            if (code !== 0) {
                storeRoot.error = true;
                storeRoot.errorMessage = qsTr("Failed to install plugin %1").arg(installProc.pendingId);
                console.log("PluginStore: install error for", installProc.pendingId, ":", installErr.text, installOut.text);
            } else {
                console.log("PluginStore: install success for", installProc.pendingId);
                if (installProc.pendingRestart)
                    storeRoot.restartRequired = true;
                // Track as installed for UI prediction (predicted post-restart state)
                let ids = storeRoot.installedPluginIds.slice();
                if (ids.indexOf(installProc.pendingId) === -1)
                    ids.push(installProc.pendingId);
                storeRoot.installedPluginIds = ids;
                console.log("PluginStore: installedPluginIds now:", JSON.stringify(ids));
                // Also add to installed tab list
                PluginLoader.addPluginToAvailable(installProc.pendingId, installProc.pendingTargetDir, "user");
            }
        }
    }

    // ── 3. Remove a user plugin ───────────────────────────────────────────────

    Process {
        id: removeProc

        property string pendingId: ""
        property bool pendingRestart: false

        onExited: (code) => {
            if (removeProc.pendingRestart)
                storeRoot.restartRequired = true;
            // Remove from predicted installed set
            let ids = storeRoot.installedPluginIds.slice();
            let idx = ids.indexOf(removeProc.pendingId);
            if (idx !== -1) ids.splice(idx, 1);
            storeRoot.installedPluginIds = ids;
            console.log("PluginStore: removed", removeProc.pendingId, "installedPluginIds now:", JSON.stringify(ids));
            // Also drop from the installed tab list model
            PluginLoader.removePluginFromAvailable(removeProc.pendingId);
        }
    }
}
