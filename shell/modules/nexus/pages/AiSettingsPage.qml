pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("AI Assistant")

    // API key entry for one provider. The value is pushed back out through
    // committed() so each instance keeps a plain static binding to its own
    // config field rather than looking one up by name.
    component ApiKeyField: ColumnLayout {
        id: keyField

        property string value
        property string envName

        signal committed(string v)

        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        ConnectedRect {
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: keyRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: keyRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    text: qsTr("API key")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurface
                }
                StyledInputField {
                    id: keyInput

                    Layout.fillWidth: true
                    horizontalAlignment: TextInput.AlignLeft
                    text: keyField.value
                    onEditingFinished: keyField.committed(text)
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.largeIncreased
            text: qsTr("Stored in your session keyring, not in shell.json. The %1 environment variable overrides it.").arg(keyField.envName)
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            wrapMode: Text.Wrap
        }

        // Re-read the stored value once a write attempt finishes. Typing breaks
        // the text binding above, so without this a failed save would keep
        // showing a key that never reached the keyring.
        Connections {
            function onKeyringRevisionChanged(): void {
                keyInput.text = keyField.value;
            }

            target: root
        }
    }

    // Keys are held in the session keyring, not shell.json — see AiAssistant.
    property var keyringKeys: ({})

    // Bumped after every write attempt so an open field re-reads what the
    // keyring actually holds instead of keeping whatever was typed into it.
    property int keyringRevision: 0

    // The key write currently in flight, plus any that arrived while it was
    // running. secret-tool calls are serialised because the Process below holds
    // a single command: starting a second write mid-flight would leave the
    // first one's exit code being applied to the second one's value, marking a
    // key as saved that was never stored.
    property string pendingProvider: ""

    property string pendingKey: ""

    property var queuedKeyWrites: []

    property string lastKeyStoreError: ""

    function apiKeyFor(p) {
        return root.keyringKeys[p] || "";
    }

    function setApiKey(p, key) {
        const m = root.keyringKeys;
        m[p] = key;
        root.keyringKeys = Object.assign({}, m);
    }

    function storeApiKey(p, key) {
        // editingFinished also fires when the field merely loses focus, so a
        // commit carrying the value already in the keyring is not a write.
        if (key === root.apiKeyFor(p))
            return;

        if (keyStoreProc.running) {
            root.queuedKeyWrites = root.queuedKeyWrites.concat([{ provider: p, key: key }]);
            return;
        }

        root.startKeyStore(p, key);
    }

    function startKeyStore(p, key) {
        root.pendingProvider = p;
        root.pendingKey = key;
        root.lastKeyStoreError = "";

        const attr = "caelestia-ai-" + p;
        const script = key === ""
            ? "secret-tool clear service caelestia key " + JSON.stringify(attr)
            : "printf %s \"$1\" | secret-tool store --label=" + JSON.stringify("Caelestia " + p + " API key") +
              " service caelestia key " + JSON.stringify(attr);
        keyStoreProc.command = key === "" ? ["sh", "-c", script] : ["sh", "-c", script, "--", key];
        keyStoreProc.running = true;
    }

    // Apply the result of the write that just finished. keyringKeys is not
    // touched until secret-tool has actually succeeded, so a missing binary, a
    // locked keyring or a rejected store can no longer leave the field showing a
    // key that was never persisted (#652).
    function finishKeyStore(code, detail) {
        const p = root.pendingProvider;
        const key = root.pendingKey;
        const clearing = key === "";
        root.pendingProvider = "";
        root.pendingKey = "";

        if (code === 0) {
            root.setApiKey(p, key);

            // Removing a key is its own visible outcome; only announce saves.
            if (!clearing)
                Toaster.toast(qsTr("API key saved"), p, "key");
        } else {
            const reason = detail !== "" ? detail : qsTr("secret-tool exited with code %1").arg(code);
            Toaster.toast(clearing ? qsTr("Couldn't remove API key") : qsTr("Couldn't save API key"),
                reason, "key_off", Toast.Error);
        }

        root.keyringRevision += 1;

        if (root.queuedKeyWrites.length > 0) {
            const next = root.queuedKeyWrites[0];
            root.queuedKeyWrites = root.queuedKeyWrites.slice(1);
            root.startKeyStore(next.provider, next.key);
        }
    }

    // ── Ollama ────────────────────────────────────────────────
    // The toggle below only flips a config bool. Without a status check the
    // assistant just fails to connect when the daemon is missing, and nothing
    // in the UI says why (issue #654).
    property string ollamaVersion: ""

    property string ollamaService: ""

    property bool ollamaInstalling: false

    property string ollamaInstallStatus: ""

    readonly property bool ollamaInstalled: ollamaVersion !== "" && ollamaVersion !== "NOT_INSTALLED"

    readonly property bool ollamaActionVisible: GlobalConfig.ai.enableOllama && ollamaVersion !== "" && !ollamaInstalled

    readonly property string ollamaStatusText: {
        if (ollamaVersion === "")
            return qsTr("Checking…");
        if (!ollamaInstalled)
            return qsTr("Not installed");
        const m = (ollamaVersion || "").match(/[0-9]+\.[0-9]+\.[0-9]+/);
        return m ? m[0] : ollamaVersion;
    }

    readonly property string ollamaHintText: {
        if (ollamaInstallStatus !== "")
            return ollamaInstallStatus;
        if (ollamaInstalled && (ollamaService === "inactive" || ollamaService === "failed"))
            return qsTr("Daemon not running - start it with: sudo systemctl start ollama");
        return "";
    }

    property string claudeVersion: ""

    readonly property bool claudeInstalled: claudeVersion !== "" && claudeVersion !== "NOT_INSTALLED"

    property bool installing: false

    property string installStatus: ""

    // The installer is never piped straight into a shell: it is downloaded to a
    // temp file first, then shown to the user (source + size) for an explicit
    // confirmation before anything from the network is executed.
    // "downloading" -> "confirm" -> "running"
    property string installStage: "idle"

    property string downloadedInstallerPath: ""

    property int downloadedInstallerSize: 0

    // The only source an installer may be fetched from; shown verbatim in the
    // confirmation step.
    readonly property string claudeInstallerUrl: "https://claude.ai/install.sh"

    // `claude --version` prints "2.1.220 (Claude Code)"; the bare number is what
    // reads well next to the published one.
    readonly property string claudeVersionShort: {
        const m = (claudeVersion || "").match(/[0-9]+\.[0-9]+\.[0-9]+/);
        return m ? m[0] : claudeVersion;
    }

    // Ask what the newest published version is whenever this page is opened, so
    // the button below is offering the right action rather than a stale one.
    Component.onCompleted: {
        UpdateChecker.checkClaudeCodeUpdate();
        loadStoredKeys();
    }

    function loadStoredKeys() {
        // opencode go shares the zen entry, so it is not listed separately.
        const provs = ["claude", "openai", "gemini", "openrouter", "opencode"];
        for (let i = 0; i < provs.length; i++)
            keyLoadComp.createObject(root, { provider: provs[i] });
    }

    function homeDir() {
        return Quickshell.env("HOME") || "";
    }

    function claudeBin() {
        return homeDir() + "/.local/bin/claude";
    }

    function ollamaScriptPath() {
        return Quickshell.shellPath("scripts/ollama_setup.sh");
    }

    function refreshStatus() {
        statusProc.running = false;
        statusProc.running = true;
    }

    // Run the confirmed installer. The path is a mktemp file the download
    // stage produced; it runs as an argv element, never through a shell string.
    function runInstaller() {
        if (installStage !== "confirm" || downloadedInstallerPath === "")
            return;
        installStage = "running";
        installStatus = qsTr("Installing…");
        installerRunProc.command = ["bash", downloadedInstallerPath];
        installerRunProc.running = true;
    }

    // Drop the downloaded installer without running it.
    function cancelInstaller() {
        if (downloadedInstallerPath !== "") {
            Quickshell.execDetached(["rm", "-f", downloadedInstallerPath]);
            downloadedInstallerPath = "";
        }
        downloadedInstallerSize = 0;
        installStage = "idle";
        installing = false;
        installStatus = "";
    }

    function refreshOllamaStatus() {
        ollamaStatusProc.running = false;
        ollamaStatusProc.running = true;
    }

    // Real login names / emails resolved from each account's .claude.json.
    property var resolvedNames: ({})

    property var resolvedEmails: ({})

    function accountJsonPath(id) {
        if (!id || id === "")
            return homeDir() + "/.claude.json";
        return homeDir() + "/.config/caelestia/claude/" + id + "/.claude.json";
    }

    function accountIds() {
        const a = accounts();
        const ids = [];
        for (let i = 0; i < a.length; i++)
            ids.push(a[i].id);
        return ids;
    }

    function displayName(id, fallback) {
        return resolvedNames[id] || fallback;
    }

    // ---- Account helpers (mirror AiAssistant's model) ----
    function accounts() {
        const list = [{ id: "", name: qsTr("Default"), dir: "" }];
        try {
            const parsed = JSON.parse(GlobalConfig.ai.claudeAccountsJson || "[]");
            if (Array.isArray(parsed))
                for (let i = 0; i < parsed.length; i++) {
                    const a = parsed[i];
                    if (a && a.id)
                        list.push({
                            id: String(a.id),
                            name: String(a.name || a.id),
                            dir: root.homeDir() + "/.config/caelestia/claude/" + String(a.id)
                        });
                }
        } catch (e) {}
        return list;
    }

    function accountDir(id) {
        const a = accounts();
        for (let i = 0; i < a.length; i++)
            if (a[i].id === id)
                return a[i].dir;
        return "";
    }

    function rawAccounts() {
        try {
            const p = JSON.parse(GlobalConfig.ai.claudeAccountsJson || "[]");
            if (Array.isArray(p))
                return p;
        } catch (e) {}
        return [];
    }

    function addAndLogin() {
        const arr = rawAccounts();
        const id = "acc_" + Date.now();
        arr.push({ id: id, name: qsTr("Account") + " " + (arr.length + 1) });
        GlobalConfig.ai.claudeAccountsJson = JSON.stringify(arr);
        GlobalConfig.ai.activeClaudeAccount = id;
        loginActive();
    }
    // Drop any added account whose login resolves to an email already used by an
    // earlier account (default first) — e.g. logging a new slot into the same account.

    function dedupAccounts() {
        const arr = rawAccounts();
        const seen = {};
        const def = resolvedEmails[""];
        if (def)
            seen[def] = true;
        const kept = [];
        let removedActive = false;
        for (let i = 0; i < arr.length; i++) {
            const a = arr[i];
            const em = resolvedEmails[a.id];
            if (em && seen[em]) {
                if ((GlobalConfig.ai.activeClaudeAccount || "") === a.id)
                    removedActive = true;
                continue;
            }
            if (em)
                seen[em] = true;
            kept.push(a);
        }
        if (kept.length !== arr.length) {
            GlobalConfig.ai.claudeAccountsJson = JSON.stringify(kept);
            if (removedActive)
                GlobalConfig.ai.activeClaudeAccount = "";
        }
    }

    function removeAccount(id) {
        if (!id || id === "")
            return; // the Default (~/.claude) account is the system login — not removable
        const arr = rawAccounts().filter(a => a && a.id !== id);
        GlobalConfig.ai.claudeAccountsJson = JSON.stringify(arr);
        if ((GlobalConfig.ai.activeClaudeAccount || "") === id)
            GlobalConfig.ai.activeClaudeAccount = "";
    }
    // Log out the Default (~/.claude) login so a different account can sign in.
    // This clears the CLI's base credentials (WinTone01), not the Claude Desktop app.

    function logoutDefault() {
        logoutProc.command = ["sh", "-c", JSON.stringify(root.claudeBin()) + " auth logout"];
        logoutProc.running = true;
    }

    function loginActive() {
        const id = GlobalConfig.ai.activeClaudeAccount || "";
        const dir = accountDir(id);
        const term = GlobalConfig.ai.loginTerminal || "konsole";
        let inner = "";
        if (dir !== "")
            inner = "mkdir -p " + JSON.stringify(dir) + "; export CLAUDE_CONFIG_DIR=" + JSON.stringify(dir) + "; ";
        inner += JSON.stringify(root.claudeBin()) + " auth login; echo; echo " + JSON.stringify(qsTr("Login done? You can close this window.")) + "; read -n1";
        loginProc.command = [term, "-e", "sh", "-lc", inner];
        loginProc.running = true;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Non-visual helpers live inside the single Item child (PageBase's default
        // property is one Item; Process objects are kept as layout resources).
        Process {
            id: keyStoreProc

            stderr: StdioCollector {
                onStreamFinished: root.lastKeyStoreError = (text || "").trim()
            }

            // Qt.callLater so the stderr collector's handler gets a chance to run
            // first. Reading lastKeyStoreError straight from here can race the
            // stream and lose the reason secret-tool gave.
            onExited: code => Qt.callLater(() => root.finishKeyStore(code, root.lastKeyStoreError))
        }

        Component {
            id: keyLoadComp

            Process {
                id: kl

                required property string provider

                running: true
                command: ["secret-tool", "lookup", "service", "caelestia", "key", "caelestia-ai-" + provider]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const k = (text || "").trim();
                        if (k !== "")
                            root.setApiKey(kl.provider, k);
                        kl.destroy();
                    }
                }
            }
        }

        Process {
            id: statusProc

            running: true
            command: ["sh", "-c", "test -x " + JSON.stringify(root.claudeBin()) + " && " + JSON.stringify(root.claudeBin()) + " --version 2>/dev/null || echo NOT_INSTALLED"]
            stdout: StdioCollector {
                onStreamFinished: root.claudeVersion = (text || "").trim()
            }
        }

        // Stage 1: download the installer to a temp file. Nothing executes
        // here; curl -f refuses to keep a partial file on HTTP errors, and the
        // ERR trap removes the temp file if the download fails, so a failed
        // download can never be executed. The URL is a fixed constant passed
        // as an argv element.
        Process {
            id: installerDownloadProc

            command: ["bash", "-c", `set -euo pipefail
TMP=$(mktemp /tmp/caelestia-claude-install.XXXXXX.sh)
trap 'rm -f "$TMP"' ERR
curl -fL --proto '=https' --tlsv1.2 -o "$TMP" "$1"
printf 'PATH=%s\\nSIZE=%s\\n' "$TMP" "$(wc -c < "$TMP")"`, "--", root.claudeInstallerUrl]

            stdout: StdioCollector {
                id: installerDownloadOut
            }
            stderr: SplitParser {
                onRead: line => root.installStatus = line
            }

            onExited: (code) => {
                if (code !== 0) {
                    // curl -f: nothing usable was kept, nothing will run.
                    root.installStage = "idle";
                    root.installing = false;
                    root.installStatus = qsTr("Download failed") + " (" + code + ")";
                    return;
                }
                let path = "";
                let size = 0;
                const lines = (installerDownloadOut.text || "").split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("PATH=") === 0)
                        path = lines[i].slice(5).trim();
                    else if (lines[i].indexOf("SIZE=") === 0)
                        size = parseInt(lines[i].slice(5), 10) || 0;
                }
                if (path === "") {
                    root.installStage = "idle";
                    root.installing = false;
                    root.installStatus = qsTr("Download failed");
                    return;
                }
                root.downloadedInstallerPath = path;
                root.downloadedInstallerSize = size;
                root.installStage = "confirm";
                root.installStatus = "";
            }
        }

        // Stage 2: run the installer the user just confirmed.
        Process {
            id: installerRunProc

            stdout: SplitParser {
                onRead: line => root.installStatus = line
            }
            stderr: SplitParser {
                onRead: line => root.installStatus = line
            }
            onExited: (code) => {
                // The temp installer is single-use; remove it either way.
                if (root.downloadedInstallerPath !== "") {
                    Quickshell.execDetached(["rm", "-f", root.downloadedInstallerPath]);
                    root.downloadedInstallerPath = "";
                }
                root.downloadedInstallerSize = 0;
                root.installStage = "idle";
                root.installing = false;
                root.installStatus = code === 0 ? qsTr("Installed.") : (qsTr("Failed") + " (" + code + ")");
                root.refreshStatus();
                // Re-read both versions so the button settles on "Check for
                // updates" instead of still offering the update just applied.
                UpdateChecker.checkClaudeCodeUpdate();
            }
        }

        // Ollama is a system service with a CLI, so the status and the install
        // both belong to the script: --status needs no privileges, and the
        // install goes through pkexec, which is what asks for the password.
        Process {
            id: ollamaStatusProc

            running: true
            command: ["bash", root.ollamaScriptPath(), "--status"]
            stdout: SplitParser {
                onRead: line => {
                    const t = (line || "").trim();
                    if (t.startsWith("VERSION="))
                        root.ollamaVersion = t.slice(8) || "unknown";
                    else if (t.startsWith("SERVICE="))
                        root.ollamaService = t.slice(8);
                }
            }
        }

        Process {
            id: ollamaInstallProc

            command: ["pkexec", "bash", root.ollamaScriptPath(), "--models", GlobalConfig.ai.defaultOllamaModel || "llama3"]
            stdout: SplitParser {
                onRead: line => root.ollamaInstallStatus = line
            }
            stderr: SplitParser {
                onRead: line => root.ollamaInstallStatus = line
            }
            onExited: code => {
                root.ollamaInstalling = false;
                if (code === 0)
                    root.ollamaInstallStatus = qsTr("Installed.");
                else if (code === 126)
                    root.ollamaInstallStatus = qsTr("Cancelled."); // pkexec: prompt dismissed
                else
                    root.ollamaInstallStatus = qsTr("Failed") + " (" + code + ")";
                root.refreshOllamaStatus();
            }
        }

        Process {
            id: loginProc
        }

        Process {
            id: logoutProc

            onExited: root.refreshStatus()
        }

        // Resolve real login names from each account's .claude.json.
        Instantiator {
            model: root.accountIds()
            delegate: FileView {
                required property string modelData

                path: root.accountJsonPath(modelData)
                printErrors: false
                watchChanges: false
                onLoaded: {
                    try {
                        const d = JSON.parse(text());
                        const oa = d.oauthAccount || {};
                        const email = oa.emailAddress || "";
                        const nm = oa.displayName || email || "";
                        if (nm) {
                            const map = root.resolvedNames;
                            map[modelData] = nm;
                            root.resolvedNames = Object.assign({}, map);
                        }
                        if (email) {
                            const em = root.resolvedEmails;
                            em[modelData] = email;
                            root.resolvedEmails = Object.assign({}, em);
                            root.dedupAccounts();
                        }
                    } catch (e) {}
                }
            }
        }

        SectionHeader {
            first: true
            text: qsTr("Local provider")
        }

        ToggleRow {
            first: true
            last: !GlobalConfig.ai.enableOllama
            text: qsTr("Ollama")
            checked: GlobalConfig.ai.enableOllama
            onToggled: GlobalConfig.ai.enableOllama = checked
        }

        InfoRow {
            visible: GlobalConfig.ai.enableOllama
            last: !root.ollamaActionVisible
            label: qsTr("Status")
            value: root.ollamaStatusText
            subtext: root.ollamaHintText
        }

        NavRow {
            visible: root.ollamaActionVisible
            last: true
            icon: "download"
            label: qsTr("Download Ollama")
            status: root.ollamaInstalling ? (root.ollamaInstallStatus || qsTr("Installing…")) : root.ollamaInstallStatus
            onClicked: {
                if (root.ollamaInstalling)
                    return;
                root.ollamaInstalling = true;
                root.ollamaInstallStatus = qsTr("Installing…");
                ollamaInstallProc.running = true;
            }
        }

        SectionHeader {
            text: qsTr("Claude")
        }

        ToggleRow {
            first: true
            text: qsTr("Claude Code")
            subtext: qsTr("Uses the Claude CLI and your Claude login")
            checked: GlobalConfig.ai.enableClaudeCode
            onToggled: GlobalConfig.ai.enableClaudeCode = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Claude API")
            subtext: qsTr("Pay-per-token API with an Anthropic key")
            checked: GlobalConfig.ai.enableClaude
            onToggled: GlobalConfig.ai.enableClaude = checked
        }

        SectionHeader {
            text: qsTr("Other providers")
        }

        ToggleRow {
            first: true
            text: qsTr("OpenAI (ChatGPT)")
            subtext: qsTr("Pay-per-token API with an OpenAI key")
            checked: GlobalConfig.ai.enableOpenai
            onToggled: GlobalConfig.ai.enableOpenai = checked
        }

        ToggleRow {
            text: qsTr("Gemini")
            subtext: qsTr("Google's OpenAI-compatible endpoint")
            checked: GlobalConfig.ai.enableGemini
            onToggled: GlobalConfig.ai.enableGemini = checked
        }

        ToggleRow {
            text: qsTr("OpenRouter")
            subtext: qsTr("One key for models from multiple vendors")
            checked: GlobalConfig.ai.enableOpenrouter
            onToggled: GlobalConfig.ai.enableOpenrouter = checked
        }

        ToggleRow {
            text: qsTr("opencode Zen")
            subtext: qsTr("Curated coding models, pay as you go")
            checked: GlobalConfig.ai.enableOpencode
            onToggled: GlobalConfig.ai.enableOpencode = checked
        }

        ToggleRow {
            last: true
            text: qsTr("opencode Go")
            subtext: qsTr("Monthly subscription; shares Zen's key")
            checked: GlobalConfig.ai.enableOpencodeGo
            onToggled: GlobalConfig.ai.enableOpencodeGo = checked
        }

        SectionHeader {
            visible: GlobalConfig.ai.enableClaude
                     || GlobalConfig.ai.enableOpenai
                     || GlobalConfig.ai.enableGemini
                     || GlobalConfig.ai.enableOpenrouter
                     || GlobalConfig.ai.enableOpencode
                     || GlobalConfig.ai.enableOpencodeGo
            text: qsTr("API keys")
        }

        // Show key fields only for enabled API providers.
        ApiKeyField {
            visible: GlobalConfig.ai.enableClaude
            value: root.apiKeyFor("claude")
            envName: "ANTHROPIC_API_KEY"
            onCommitted: v => root.storeApiKey("claude", v)
        }

        ApiKeyField {
            visible: GlobalConfig.ai.enableOpenai
            value: root.apiKeyFor("openai")
            envName: "OPENAI_API_KEY"
            onCommitted: v => root.storeApiKey("openai", v)
        }

        ApiKeyField {
            visible: GlobalConfig.ai.enableGemini
            value: root.apiKeyFor("gemini")
            envName: "GEMINI_API_KEY"
            onCommitted: v => root.storeApiKey("gemini", v)
        }

        ApiKeyField {
            visible: GlobalConfig.ai.enableOpenrouter
            value: root.apiKeyFor("openrouter")
            envName: "OPENROUTER_API_KEY"
            onCommitted: v => root.storeApiKey("openrouter", v)
        }

        // opencode Zen and Go share one account key.
        ApiKeyField {
            visible: GlobalConfig.ai.enableOpencode || GlobalConfig.ai.enableOpencodeGo
            value: root.apiKeyFor("opencode")
            envName: "OPENCODE_API_KEY"
            onCommitted: v => root.storeApiKey("opencode", v)
        }

        // ── Claude Code ────────────────────────────────────────────
        // Everything below is only meaningful while the provider is on.
        SectionHeader {
            visible: GlobalConfig.ai.enableClaudeCode
            text: qsTr("Claude Code")
        }

        InfoRow {
            visible: GlobalConfig.ai.enableClaudeCode
            first: true
            label: qsTr("Status")
            value: {
                if (!root.claudeInstalled)
                    return qsTr("Not installed");
                if (UpdateChecker.claudeCodeHasUpdate)
                    return root.claudeVersionShort + " → " + UpdateChecker.claudeCodeLatestVersion;
                return root.claudeVersionShort;
            }
        }
        NavRow {
            visible: GlobalConfig.ai.enableClaudeCode
            // One button, three jobs: install it, update it, or — when it is
            // already current — re-check whether that is still true.
            icon: root.claudeInstalled && !UpdateChecker.claudeCodeHasUpdate ? "refresh" : "download"
            label: {
                if (!root.claudeInstalled)
                    return qsTr("Download Claude Code");
                if (UpdateChecker.claudeCodeHasUpdate)
                    return qsTr("Update Claude Code");
                return qsTr("Check for updates");
            }
            status: {
                if (root.installStage === "confirm")
                    return qsTr("Review the download before running it");
                if (root.installing)
                    return root.installStatus || qsTr("Installing…");
                if (UpdateChecker.claudeCodeChecking)
                    return qsTr("Checking…");
                if (root.installStatus !== "")
                    return root.installStatus;
                if (root.claudeInstalled && !UpdateChecker.claudeCodeHasUpdate && UpdateChecker.claudeCodeLatestVersion !== "")
                    return qsTr("Up to date");
                return "";
            }
            onClicked: {
                if (root.installing || UpdateChecker.claudeCodeChecking)
                    return;
                // Up to date — the button is a re-check, not a reinstall.
                if (root.claudeInstalled && !UpdateChecker.claudeCodeHasUpdate) {
                    root.installStatus = "";
                    UpdateChecker.checkClaudeCodeUpdate();
                    return;
                }
                root.installing = true;
                root.installStage = "downloading";
                root.installStatus = qsTr("Downloading…");
                installerDownloadProc.running = true;
            }
        }

        // Explicit review step before anything from the network is executed:
        // the downloaded installer is shown with its exact source and size and
        // only runs after the user confirms.
        ConnectedRect {
            id: installerConfirmRect

            visible: root.installStage === "confirm"
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: installerConfirmColumn.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: installerConfirmColumn

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("The installer has been downloaded and is ready to run:")
                    font: Tokens.font.title.small
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Source: %1").arg(root.claudeInstallerUrl)
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Size: %1 kB").arg((root.downloadedInstallerSize / 1024).toFixed(1))
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("The file runs with your user permissions. Only continue if you trust this source.")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    spacing: Tokens.spacing.medium

                    Item { Layout.fillWidth: true }
                    TextButton {
                        text: qsTr("Cancel")
                        type: TextButton.Text
                        onClicked: root.cancelInstaller()
                    }
                    TextButton {
                        text: qsTr("Run installer")
                        type: TextButton.Filled
                        onClicked: root.runInstaller()
                    }
                }
            }
        }

        // Unrestricted mode (off by default): while enabled, every Claude Code
        // session is spawned with --dangerously-skip-permissions, i.e. it runs
        // commands and edits files without asking first.
        ToggleRow {
            visible: GlobalConfig.ai.enableClaudeCode
            last: !unrestrictedWarning.visible
            text: qsTr("Unrestricted mode")
            subtext: qsTr("Let Claude Code run commands without asking")
            checked: GlobalConfig.ai.claudeCodeSkipPermissions
            onToggled: GlobalConfig.ai.claudeCodeSkipPermissions = checked
        }

        // The warning stays visible for as long as unrestricted mode is on.
        ConnectedRect {
            id: unrestrictedWarning

            visible: GlobalConfig.ai.enableClaudeCode && GlobalConfig.ai.claudeCodeSkipPermissions
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: unrestrictedWarningLayout.implicitHeight + Tokens.padding.largeIncreased * 2

            RowLayout {
                id: unrestrictedWarningLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignTop
                    text: "warning"
                    color: Colours.palette.m3error
                    fontStyle: Tokens.font.icon.large
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Unrestricted mode is on: Claude Code executes commands and edits files without asking. Turn this off if that is not what you want.")
                    wrapMode: Text.WordWrap
                    font: Tokens.font.body.small
                }
            }
        }

        // ── Accounts ───────────────────────────────────────────────
        SectionHeader {
            visible: GlobalConfig.ai.enableClaudeCode
            text: qsTr("Claude accounts")
        }
        Repeater {
            model: root.accounts()

            ConnectedRect {
                id: accRect

                required property var modelData
                required property int index

                readonly property bool isActive: (GlobalConfig.ai.activeClaudeAccount || "") === modelData.id
                readonly property bool isDefault: modelData.id === ""

                visible: GlobalConfig.ai.enableClaudeCode
                Layout.fillWidth: true
                first: index === 0
                implicitHeight: accRow.implicitHeight + Tokens.padding.medium * 2

                StateLayer {
                    onClicked: GlobalConfig.ai.activeClaudeAccount = accRect.modelData.id
                }

                RowLayout {
                    id: accRow

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: accRect.isActive ? "check_circle" : "person"
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.displayName(accRect.modelData.id, accRect.modelData.name)
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: accRect.isActive ? qsTr("Active") : qsTr("Tap to select")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    // Named accounts get a delete button; the Default (system login)
                    // gets a log-out button that clears its ~/.claude credentials.
                    MaterialIcon {
                        text: accRect.isDefault ? "logout" : "delete"
                        color: delMouse.containsMouse ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant

                        MouseArea {
                            id: delMouse

                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: accRect.isDefault ? root.logoutDefault() : root.removeAccount(accRect.modelData.id)
                        }

                        Behavior on color {
                            CAnim {}
                        }
                    }
                }
            }
        }
        NavRow {
            visible: GlobalConfig.ai.enableClaudeCode
            icon: "login"
            label: qsTr("Log in to selected account")
            status: root.claudeInstalled ? "" : qsTr("Install Claude Code first")
            onClicked: {
                if (root.claudeInstalled)
                    root.loginActive();
            }
        }
        NavRow {
            visible: GlobalConfig.ai.enableClaudeCode
            last: true
            icon: "person_add"
            label: qsTr("Add another account & log in")
            status: root.claudeInstalled ? qsTr("Log into a different Claude account") : qsTr("Install Claude Code first")
            onClicked: {
                if (root.claudeInstalled)
                    root.addAndLogin();
            }
        }
    }
}
