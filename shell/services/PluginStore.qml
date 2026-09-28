pragma Singleton

import qs.services.api
import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

Item {
    id: storeRoot

    property bool loading: false
    property bool error: false
    property string errorMessage: ""

    property bool installing: false
    property string installProgress: ""

    property bool restartRequired: false

    property var installedPluginIds: []
    property bool baselineLoaded: false

    property var indexData: null
    property ListModel storePlugins: ListModel {}

    signal indexFetched()
    signal installedStateChanged()

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

        fetchProc.command = ["curl", "-sfL", "https://raw.githubusercontent.com/ladybug-me/caelestia-kde-plugins/" + fetchBranch + "/index.json"];
        fetchProc.running = true;
    }

    function installPlugin(id, repoPath, branch, restart) {
        if (!id) return;

        let installBranch = branch || "main";

        let actualRepoPath = repoPath || ("plugins/" + id);

        installing = true;
        installProgress = "Cloning plugin '" + id + "'...";

        let targetDir = (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/caelestia/plugins/" + id;

        let script = `set -e
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git init -q
git remote add origin https://github.com/ladybug-me/caelestia-kde-plugins.git
git config core.sparseCheckout true
echo "$2/*" >> .git/info/sparse-checkout
git fetch -q --depth 1 --filter=blob:none origin "$3"
git reset --hard -q "origin/$3"
mkdir -p "$(dirname "$4")"
rm -rf "$4"
mv "$2" "$4"
rm -rf "$TMP_DIR"
echo "DONE"`;

        installProc.pendingId = id;
        installProc.pendingTargetDir = targetDir;
        installProc.pendingRestart = (restart === "true" || restart === true);
        installProc.command = ["bash", "-c", script, "--", id, actualRepoPath, installBranch, targetDir];
        installProc.running = true;
    }

    function removePlugin(id) {
        let targetDir = (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/caelestia/plugins/" + id;
        removeProc.pendingId = id;
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
                console.log("PluginStore: install error for", installProc.pendingId, ":", installErr.text, installOut.text);
            } else {
                console.log("PluginStore: install success for", installProc.pendingId);
                if (installProc.pendingRestart)
                    storeRoot.restartRequired = true;
                let ids = storeRoot.installedPluginIds.slice();
                if (ids.indexOf(installProc.pendingId) === -1)
                    ids.push(installProc.pendingId);
                storeRoot.installedPluginIds = ids;
                console.log("PluginStore: installedPluginIds now:", JSON.stringify(ids));
                PluginLoader.addPluginToAvailable(installProc.pendingId, installProc.pendingTargetDir, "user");
            }
        }
    }


    Process {
        id: removeProc

        property string pendingId: ""
        property bool pendingRestart: false

        onExited: (code) => {
            if (removeProc.pendingRestart)
                storeRoot.restartRequired = true;
            let ids = storeRoot.installedPluginIds.slice();
            let idx = ids.indexOf(removeProc.pendingId);
            if (idx !== -1) ids.splice(idx, 1);
            storeRoot.installedPluginIds = ids;
            console.log("PluginStore: removed", removeProc.pendingId, "installedPluginIds now:", JSON.stringify(ids));
            PluginLoader.removePluginFromAvailable(removeProc.pendingId);
        }
    }
}
