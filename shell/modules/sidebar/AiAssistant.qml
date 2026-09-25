pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import M3Shapes
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    ListModel { id: chatHistory }
    ListModel { id: historySessionsModel }

    property bool isHistoryTab: false

    property string currentChatId: ""

    property var currentRequest: null
    

    Timer {
        id: typingTimer

        interval: 16
        repeat: true

        property string fullText: ""

        property string currentText: ""

        property int charIndex: 0

        property int targetIdx: -1
        
        onTriggered: {
            if (targetIdx < 0 || targetIdx >= chatHistory.count) {
                stop();
                isTyping = false;
                isThinking = false;
                inAgentLoop = false;
                return;
            }
            if (charIndex >= fullText.length) {
                stop();
                chatHistory.setProperty(targetIdx, "text", fullText);
                chatHistory.setProperty(targetIdx, "isFinished", true);
                saveHistory();
                isTyping = false;
                isThinking = false;
                inAgentLoop = false;
                return;
            }
            var chunkSize = Math.max(1, Math.ceil(fullText.length / 30));
            currentText += fullText.substr(charIndex, chunkSize);
            charIndex += chunkSize;
            chatHistory.setProperty(targetIdx, "text", currentText);
            listView.positionViewAtEnd();
        }
    }
    
    property real savedContentY: -1

    // Refresh the model list when switching to an OpenAI-compatible provider, so a
    // key added after startup takes effect without a reload.
    onProviderChanged: {
        cancelRateLimitRetry();
        if (isOpenaiCompat)
            fetchOpenaiCompatModels(provider);
        else if (isClaude)
            fetchClaudeModels();
    }

    onVisibleChanged: {
        if (visible) {
            refreshAllModels();
            if (savedContentY >= 0) {
                Qt.callLater(function() { listView.contentY = savedContentY; });
            }
        } else {
            savedContentY = listView.contentY;
        }
    }

    function startTypingAnimation(text) {
        isThinking = false;
        typingTimer.targetIdx = chatHistory.count - 1;
        typingTimer.fullText = text;
        typingTimer.currentText = "";
        typingTimer.charIndex = 0;
        typingTimer.start();
        listView.positionViewAtEnd();
    }

    // Ask every enabled provider what it offers, rather than shipping lists that
    // go stale each time a vendor releases a model.
    function refreshAllModels() {
        fetchOllamaModels();
        fetchClaudeCodeModels();
        fetchClaudeModels();
        const compat = root.openaiCompatProviders;
        for (var i = 0; i < compat.length; i++) {
            if (providerList.indexOf(compat[i]) !== -1)
                fetchOpenaiCompatModels(compat[i]);
        }
    }

    // The local endpoint is typed by hand, so editing the host or port has to
    // invalidate what came from the previous address — otherwise the picker keeps
    // offering the old server's models while sends go to the new one.
    function refetchLocalModels(): void {
        // Both maps are replaced rather than mutated: openaiCompatModels feeds a
        // binding, so a fresh object is what makes the picker update at all.
        const seen = Object.assign({}, root.modelsFetched);
        delete seen["local"];
        root.modelsFetched = seen;

        const models = Object.assign({}, root.openaiCompatModels);
        delete models["local"];
        root.openaiCompatModels = models;

        if (GlobalConfig.ai.enableLocal)
            root.fetchOpenaiCompatModels("local", true);
    }

    // Re-fetch when the typed address changes, so the picker never offers the
    // previous server's models while sends already go to the new one.
    Connections {
        target: GlobalConfig.ai

        onLocalHostChanged: root.refetchLocalModels()
        onLocalPortChanged: root.refetchLocalModels()
    }

    Component.onCompleted: {
        loadAllKeys();
        refreshAllModels();
        loadHistory();
    }

    // ── XHR network error handling ────────────────────────────────
    // QML's XMLHttpRequest does not fire onreadystatechange for network
    // failures (DNS, connection refused, timeout). Without an onerror
    // handler the UI silently hangs with a loading indicator forever.

    function logFetchError(provider) {
        Logger.log("[AI] Network error fetching models from " + (provider || "unknown"));
    }

    // The local address is typed by hand, so a failure there is nearly always a
    // wrong host, port, or a server that is not running. Name the endpoint that
    // was actually tried — the generic "check your connection" tells the user
    // nothing when the only connection involved is one they configured.
    function localEndpointHint(): string {
        return qsTr("Could not reach %1. Check the host and port in AI settings, and that the server is running.").arg(root.openaiCompatBase());
    }

    function handleSendError() {
        isTyping = false;
        isThinking = false;
        inAgentLoop = false;
        currentActionText = "";
        // Mark the last (assistant) bubble as failed so the user sees feedback.
        for (var ei = chatHistory.count - 1; ei >= 0; ei--) {
            var em = chatHistory.get(ei);
            if (!em.isUser && !em.isFinished) {
                chatHistory.setProperty(ei, "isFinished", true);
                if (!em.text)
                    chatHistory.setProperty(ei, "text", root.isLocal
                        ? "⚠️ " + root.localEndpointHint()
                        : "⚠️ Network error - check your connection and try again.");
                break;
            }
        }
    }

    property var ollamaModelsList: []

    // Every provider's model list is discovered from that provider, so none of
    // them need editing here when a vendor ships a new model. Anthropic's list
    // comes from GET /v1/models (needs the API key the provider requires anyway).
    property var claudeModelsList: []

    function fetchClaudeModels() {
        const key = root.getApiKeyFor("claude");
        if (key === "")
            return;
        const base = GlobalConfig.ai.anthropicUrl || "https://api.anthropic.com";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", base + "/v1/models?limit=100", true);
        xhr.setRequestHeader("x-api-key", key);
        xhr.setRequestHeader("anthropic-version", "2023-06-01");
        xhr.setRequestHeader("anthropic-dangerous-direct-browser-access", "true");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                Logger.log("[AI] Claude model list failed (status " + xhr.status + ")");
                return;
            }
            try {
                const parsed = JSON.parse(xhr.responseText);
                var list = [];
                for (var i = 0; i < (parsed.data || []).length; i++) {
                    if (parsed.data[i].id)
                        list.push(parsed.data[i].id);
                }
                if (list.length === 0)
                    return;
                // Newest first — the API returns them in creation order.
                list.reverse();
                root.claudeModelsList = list;
                if (list.indexOf(GlobalConfig.ai.defaultClaudeModel) === -1)
                    GlobalConfig.ai.defaultClaudeModel = list[0];
            } catch (e) {
                Logger.log("[AI] Error parsing Claude models: " + e.message);
            }
        };
        xhr.onerror = () => { root.logFetchError("Claude"); };
        xhr.send();
    }

    // Model choices for the Claude Code (subscription CLI) provider. "default"
    // means: don't pass --model at all and let the CLI use whatever the
    // subscription defaults to. The concrete ids are read out of the installed
    // binary by fetchClaudeCodeModels(), so they track the CLI as it updates.
    property var claudeCodeModelsList: ["default"]

    // Effort/thinking levels vary per model: recent models add xhigh/max, some support
    // fewer, and several (haiku, older sonnet, opus ≤4.1) support none at all. Returns
    // the valid levels for a given model ("" when the model has no effort control).
    function effortLevelsFor(model) {
        var m = String(model || "default").toLowerCase();
        if (m === "haiku")
            return [];
        if (m === "default" || m === "opus" || m === "sonnet" || m === "fable")
            return ["low", "medium", "high", "xhigh", "max"];

        var fam = m.indexOf("opus") !== -1 ? "opus"
                : m.indexOf("sonnet") !== -1 ? "sonnet"
                : m.indexOf("haiku") !== -1 ? "haiku"
                : m.indexOf("fable") !== -1 ? "fable" : "";
        var nums = (m.match(/\d+/g) || []).map(Number);
        var major = nums.length >= 1 ? nums[0] : 0;
        var minor = nums.length >= 2 ? nums[1] : 0;

        if (fam === "haiku")
            return [];
        if (fam === "fable")
            return ["low", "medium", "high", "xhigh", "max"];
        if (fam === "opus") {
            if (major > 4 || (major === 4 && minor >= 7))
                return ["low", "medium", "high", "xhigh", "max"];
            if (major === 4 && minor === 6)
                return ["low", "medium", "high", "max"];
            if (major === 4 && minor === 5)
                return ["low", "medium", "high"];
            return [];
        }
        if (fam === "sonnet") {
            if (major >= 5)
                return ["low", "medium", "high", "xhigh", "max"];
            if (major === 4 && minor === 6)
                return ["low", "medium", "high", "max"];
            return [];
        }
        return [];
    }

    // Effort choices for the currently-selected Claude Code model (empty = unsupported).
    readonly property var claudeCodeEffortOptions: {
        var lv = effortLevelsFor(activeModel());
        return lv.length > 0 ? ["default"].concat(lv) : [];
    }

    // Extract the model IDs the installed `claude` binary knows about (a real
    // "fetch" of what this CLI version supports), merged with the handy aliases.
    function fetchClaudeCodeModels() {
        var bin = claudeCodeBinPath();
        var script =
            "t=\"$(readlink -f " + JSON.stringify(bin) + " 2>/dev/null)\"; [ -z \"$t\" ] && t=" + JSON.stringify(bin) + "; " +
            "strings \"$t\" 2>/dev/null | grep -oE 'claude-(opus|sonnet|haiku|fable)-[0-9]+(-[0-9]+)?' | sort -u";
        var commandStr = JSON.stringify(["sh", "-c", script]);
        var qml =
            "import QtQuick\n" +
            "import Quickshell.Io\n" +
            "Process {\n" +
            "    id: mp\n" +
            "    command: " + commandStr + "\n" +
            "    stdout: StdioCollector { onStreamFinished: root.applyClaudeCodeModels(text || \"\"); }\n" +
            "    onExited: code => mp.destroy()\n" +
            "}";
        try {
            var o = Qt.createQmlObject(qml, root, "ccModelsProc");
            o.running = true;
        } catch (e) {
            Logger.log("[AI] claude-code model fetch error: " + e.message);
        }
    }

    function applyClaudeCodeModels(text) {
        // The binary also embeds unrelated strings that merely start with "claude-"
        // and long-dead models, so only ids shaped like <family>-<version> survive,
        // minus dated snapshots (…-20250514) and the ".0" aliases of a base version.
        var ids = [];
        var seen = {};
        const lines = (text || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            const id = lines[i].trim();
            if (id === "" || seen[id])
                continue;
            if (/-\d{5,}$/.test(id) || /-0$/.test(id))
                continue;
            seen[id] = true;
            ids.push(id);
        }

        // A family's bare major ("claude-opus-4") is just a stub for its newest
        // minor, so drop it when a more specific id for the same major exists.
        ids = ids.filter(id => !ids.some(other => other !== id && other.indexOf(id + "-") === 0));

        // Newest first: sort by family version, descending.
        ids.sort((a, b) => {
            const va = (a.match(/\d+/g) || []).map(Number);
            const vb = (b.match(/\d+/g) || []).map(Number);
            for (var k = 0; k < Math.max(va.length, vb.length); k++) {
                const d = (vb[k] || 0) - (va[k] || 0);
                if (d !== 0)
                    return d;
            }
            return a.localeCompare(b);
        });

        claudeCodeModelsList = ["default"].concat(ids);
    }

    // Currently selected provider ("ollama" | "claude-code" | "claude"), persisted in config.
    readonly property string provider: GlobalConfig.ai.defaultProvider || "ollama"

    readonly property bool isClaude: provider === "claude"       // Anthropic HTTP API (API key)

    readonly property bool isClaudeCode: provider === "claude-code" // `claude` CLI (subscription)

    // Runtime cache of Claude Code CLI session ids, keyed by chat id (also persisted
    // into allChatSessions so --resume works across shell restarts).
    property var claudeCodeSessions: ({})

    property var currentClaudeCodeProc: null

    // Prompt suggestions (Claude Code): starter prompts generated on demand.
    property var promptSuggestions: []

    property bool loadingSuggestions: false

    function fetchPromptSuggestions() {
        if (!isClaudeCode || loadingSuggestions)
            return;
        loadingSuggestions = true;
        promptSuggestions = [];

        // Gather recent conversation context + the current input draft so suggestions
        // are relevant to what the user is doing (not generic starters).
        var lines = [];
        for (var li = 0; li < chatHistory.count; li++) {
            var lm = chatHistory.get(li);
            if (!lm.isUser && !lm.isFinished)
                continue;
            var lt = (lm.text || "").trim();
            if (lt === "")
                continue;
            lines.push((lm.isUser ? "User" : "Assistant") + ": " + lt);
        }
        if (lines.length > 6)
            lines = lines.slice(lines.length - 6);
        var context = lines.join("\n");
        var draft = "";
        try {
            draft = (inputArea.text || "").trim();
        } catch (e) {}

        var prompt;
        if (context === "" && draft === "") {
            prompt = "Suggest exactly 4 short, varied example prompts a user might ask a helpful AI desktop assistant. Reply with ONLY a JSON array of 4 short strings, nothing else.";
        } else {
            prompt = "You are suggesting what the user might type NEXT in this chat. Based only on the context below, propose exactly 4 short, specific follow-up prompts they are likely to want to send next. Reply with ONLY a JSON array of 4 short strings, nothing else.\n\n";
            if (context !== "")
                prompt += "Conversation so far:\n" + context + "\n\n";
            if (draft !== "")
                prompt += "The user has started typing: \"" + draft + "\"\n\n";
        }

        var cmd = [claudeCodeBinPath(), "-p", prompt, "--output-format", "json", "--dangerously-skip-permissions"];
        var qml =
            "import QtQuick\n" +
            "import Quickshell.Io\n" +
            "Process {\n" +
            "    id: sp\n" +
            "    command: " + JSON.stringify(cmd) + "\n" +
            "    workingDirectory: " + JSON.stringify(claudeCodeCwd()) + "\n" +
            claudeCodeEnvSnippet() +
            "    stdout: StdioCollector { onStreamFinished: root.applyPromptSuggestions(text || \"\"); }\n" +
            "    onExited: code => { root.loadingSuggestions = false; sp.destroy(); }\n" +
            "}";
        try {
            var o = Qt.createQmlObject(qml, root, "promptSugProc");
            o.running = true;
        } catch (e) {
            loadingSuggestions = false;
            Logger.log("[AI] suggestion process error: " + e.message);
        }
    }

    function applyPromptSuggestions(text) {
        loadingSuggestions = false;
        var resultStr = "";
        try {
            resultStr = JSON.parse(text).result || "";
        } catch (e) {
            return;
        }
        var arr = null;
        try {
            arr = JSON.parse(resultStr);
        } catch (e) {
            var m = resultStr.match(/\[[\s\S]*\]/);
            if (m)
                try { arr = JSON.parse(m[0]); } catch (e2) {}
        }
        if (Array.isArray(arr)) {
            var list = [];
            for (var i = 0; i < arr.length && i < 6; i++)
                list.push(String(arr[i]));
            promptSuggestions = list;
        }
    }

    // A stored CLI session id only applies to the account that created it (session
    // ids live under that account's CLAUDE_CONFIG_DIR). If the active account differs,
    // return "" so we start a fresh session under the new account instead of a
    // --resume that would fail with "no conversation found".
    function claudeCodeSessionFor(chatId) {
        var active = GlobalConfig.ai.activeClaudeAccount || "";
        var c = claudeCodeSessions[chatId];
        if (c && c.acc === active)
            return c.sid;
        for (var i = 0; i < allChatSessions.length; i++)
            if (allChatSessions[i].id === chatId) {
                if ((allChatSessions[i].claudeCodeSessionAccount || "") === active)
                    return allChatSessions[i].claudeCodeSessionId || "";
                return "";
            }
        return "";
    }

    function setClaudeCodeSession(chatId, sid) {
        if (!sid)
            return;
        var active = GlobalConfig.ai.activeClaudeAccount || "";
        claudeCodeSessions[chatId] = { sid: sid, acc: active };
        for (var i = 0; i < allChatSessions.length; i++) {
            if (allChatSessions[i].id === chatId) {
                allChatSessions[i].claudeCodeSessionId = sid;
                allChatSessions[i].claudeCodeSessionAccount = active;
                break;
            }
        }
    }

    // Plain-text transcript of the conversation so far, used to seed a *fresh* CLI
    // session (new chat, or after switching account) with prior context. Includes the
    // latest user message and skips the streaming placeholder. Returns "" when there
    // is only the single latest message (nothing to carry over).
    function claudeCodeTranscript() {
        var lines = [];
        var count = 0;
        for (var i = 0; i < chatHistory.count; i++) {
            var m = chatHistory.get(i);
            if (!m.isUser && !m.isFinished)
                continue;
            var t = (m.text || "").trim();
            if (t === "")
                continue;
            lines.push((m.isUser ? "User: " : "Assistant: ") + t);
            count++;
        }
        if (count <= 1)
            return "";
        return "Continue this conversation. Conversation so far:\n\n" + lines.join("\n\n") + "\n\nReply to the last user message.";
    }

    // A user-supplied OpenAI-compatible endpoint: a plain llama.cpp llama-server,
    // a llama.cpp router, or anything else that serves /v1/models and
    // /v1/chat/completions. It needs no API key, so it is kept out of the key
    // paths below while still speaking the OpenAI-compatible wire format.
    readonly property bool isLocal: provider === "local"

    // Resolve the Anthropic API key: ANTHROPIC_API_KEY env var wins, config field is the fallback.
    // These providers all expose the same /models catalogue and take the same
    // /chat/completions request, so they share one model list, key handling and
    // request path, and differ only in base URL and key.
    readonly property bool isOpenaiCompat: root.openaiCompatProviders.indexOf(provider) !== -1

    // opencode is the exception: it is in the list above because it shares all of
    // that, but only for part of its catalogue — the rest needs Anthropic Messages,
    // and it authenticates with x-api-key. See opencodeWire() and setAuthHeader().
    readonly property bool isOpencode: provider === "opencode" || provider === "opencode-go"

    readonly property var openaiCompatProviders: ["openai", "gemini", "openrouter", "opencode", "opencode-go", "local"]

    function openaiCompatBase(p) {
        const which = p || provider;
        if (which === "gemini")
            return GlobalConfig.ai.geminiUrl || "https://generativelanguage.googleapis.com/v1beta/openai";
        if (which === "openrouter")
            return GlobalConfig.ai.openrouterUrl || "https://openrouter.ai/api/v1";
        if (which === "opencode")
            return GlobalConfig.ai.opencodeUrl || "https://opencode.ai/zen/v1";
        if (which === "opencode-go")
            return GlobalConfig.ai.opencodeGoUrl || "https://opencode.ai/zen/go/v1";
        if (which === "local")
            // The URL is assembled from the host and port fields by Paths, which
            // the settings page uses too, so the address shown there is the
            // address requests are actually sent to.
            return Paths.openaiCompatBase(GlobalConfig.ai.localHost, GlobalConfig.ai.localPort);
        return GlobalConfig.ai.openaiUrl || "https://api.openai.com/v1";
    }

    // Which wire format an opencode model needs. The gateway routes by model rather
    // than by product, and the split differs between zen and go — minimax is
    // OpenAI-compatible on zen but Anthropic-compatible on go — so this is keyed on
    // both. Prefixes rather than full ids, so a new point release of an existing
    // family keeps working; when opencode adds a family, this is what needs updating.
    readonly property var opencodeAnthropicPrefixes: ({
        "opencode": ["claude-", "qwen"],
        "opencode-go": ["minimax-", "qwen"]
    })

    // zen serves GPT over /responses and Gemini over /models/[id]. Neither is a
    // format the shell speaks, so those models are kept out of the picker instead
    // of being offered and then failing on send.
    readonly property var opencodeUnsupportedPrefixes: ({
        "opencode": ["gpt-", "gemini-"],
        "opencode-go": []
    })

    function opencodeWire(p, model) {
        const prefixes = root.opencodeAnthropicPrefixes[p] || [];
        for (var i = 0; i < prefixes.length; i++)
            if ((model || "").indexOf(prefixes[i]) === 0)
                return "anthropic";
        return "openai";
    }

    function opencodeSupports(p, model) {
        const prefixes = root.opencodeUnsupportedPrefixes[p] || [];
        for (var i = 0; i < prefixes.length; i++)
            if ((model || "").indexOf(prefixes[i]) === 0)
                return false;
        return true;
    }

    // True when the request for the active provider and model must be built and
    // parsed as Anthropic Messages rather than OpenAI chat completions.
    readonly property bool anthropicWire: isClaude || (isOpencode && opencodeWire(provider, activeModel()) === "anthropic")

    // opencode's /messages endpoint ignores Authorization and answers "Missing API
    // key"; x-api-key is read by both of its endpoints, so it is the one that works
    // whichever wire the chosen model needs. The others take the bearer token.
    function setAuthHeader(xhr, p) {
        const which = p || provider;
        // A local server has no key to send, and some reject an unexpected
        // Authorization header outright — leave the request unauthenticated.
        if (which === "local")
            return;
        const key = root.getApiKeyFor(which);
        if (which === "opencode" || which === "opencode-go")
            xhr.setRequestHeader("x-api-key", key);
        else
            xhr.setRequestHeader("Authorization", "Bearer " + key);
    }

    // The API key for a provider. The environment variable wins over the config
    // field, so a key exported in the session is never overridden by a stale one
    // saved in settings.
    // API keys live in the session keyring (Secret Service — KWallet on KDE,
    // gnome-keyring elsewhere), not in shell.json. A config file is world-readable
    // by anything running as the user and ends up in dotfile backups and git
    // repos; a key is not the kind of thing to leave sitting there.
    //
    // The config fields are kept only so an existing plaintext key can be moved
    // across once and then cleared.
    property var keyringKeys: ({})

    // zen and go are one opencode account, so both read and write the same entry
    // rather than making the user paste the key twice.
    function keyringOwner(p) {
        const which = p || provider;
        return which === "opencode-go" ? "opencode" : which;
    }

    function keyringAttr(p) {
        return "caelestia-ai-" + root.keyringOwner(p);
    }

    function loadKeyring(p) {
        const which = p || provider;
        const cmd = ["secret-tool", "lookup", "service", "caelestia", "key", root.keyringAttr(which)];
        const qml = 'import QtQuick\nimport Quickshell.Io\n' +
            'Process {\n    id: kp\n    command: ' + JSON.stringify(cmd) + '\n' +
            '    stdout: StdioCollector { onStreamFinished: root.onKeyringKey(' + JSON.stringify(which) + ', (text || "").trim(), kp); }\n' +
            '    onExited: code => { if (code !== 0) kp.destroy(); }\n}';
        try {
            const o = Qt.createQmlObject(qml, root, "keyringProc");
            o.running = true;
        } catch (e) {}
    }

    function onKeyringKey(p, key, proc) {
        if (key !== "") {
            const m = root.keyringKeys;
            m[p] = key;
            root.keyringKeys = Object.assign({}, m);
        }
        if (proc)
            proc.destroy();
    }

    function storeKeyring(p, key) {
        const which = root.keyringOwner(p || provider);
        const m = root.keyringKeys;
        m[which] = key;
        root.keyringKeys = Object.assign({}, m);

        const attr = root.keyringAttr(which);
        // The key goes in on stdin so it never appears in the process list.
        const script = key === ""
            ? "secret-tool clear service caelestia key " + JSON.stringify(attr)
            : "printf %s \"$1\" | secret-tool store --label=" + JSON.stringify("Caelestia " + which + " API key") +
              " service caelestia key " + JSON.stringify(attr);
        const cmd = key === "" ? ["sh", "-c", script] : ["sh", "-c", script, "--", key];
        try {
            const o = Qt.createQmlObject('import QtQuick\nimport Quickshell.Io\nProcess { id: sp; command: ' +
                JSON.stringify(cmd) + '\n onExited: code => sp.destroy() }', root, "keyringStore");
            o.running = true;
        } catch (e) {}
    }

    // Move a key that predates keyring storage out of the config, once.
    function migratePlaintextKey(p, configKey) {
        const existing = (GlobalConfig.ai[configKey] || "").trim();
        if (existing === "")
            return;
        root.storeKeyring(p, existing);
        GlobalConfig.ai[configKey] = "";
        Logger.log("[AI] moved " + p + " API key from shell.json into the keyring");
    }

    function getApiKeyFor(p) {
        const which = p || provider;
        var envName = "ANTHROPIC_API_KEY";
        var configured = GlobalConfig.ai.anthropicApiKey;
        if (which === "openai") {
            envName = "OPENAI_API_KEY";
            configured = GlobalConfig.ai.openaiApiKey;
        } else if (which === "gemini") {
            envName = "GEMINI_API_KEY";
            configured = GlobalConfig.ai.geminiApiKey;
        } else if (which === "openrouter") {
            envName = "OPENROUTER_API_KEY";
            configured = GlobalConfig.ai.openrouterApiKey;
        } else if (which === "opencode" || which === "opencode-go") {
            envName = "OPENCODE_API_KEY";
            configured = GlobalConfig.ai.opencodeApiKey;
        }
        const envKey = Quickshell.env(envName);
        if (envKey && envKey.trim() !== "")
            return envKey.trim();

        // Keyring next. A value still sitting in the config is a leftover from
        // before keyring storage — hand it back this once, migrateKeys() moves it.
        const stored = root.keyringKeys[root.keyringOwner(which)];
        if (stored && stored !== "")
            return stored;
        return (configured || "").trim();
    }

    // Config field backing each provider, used only for the one-time migration.
    readonly property var legacyKeyFields: ({
        "claude": "anthropicApiKey",
        "openai": "openaiApiKey",
        "gemini": "geminiApiKey",
        "openrouter": "openrouterApiKey",
        "opencode": "opencodeApiKey"
    })

    function loadAllKeys() {
        for (const p in root.legacyKeyFields) {
            root.loadKeyring(p);
            root.migratePlaintextKey(p, root.legacyKeyFields[p]);
        }
    }

    function getApiKey() {
        return root.getApiKeyFor(root.provider);
    }

    // Providers that need a key before they can send anything. The local server
    // is OpenAI-compatible but unauthenticated, so it is excluded here.
    readonly property bool needsApiKey: (isClaude || isOpenaiCompat) && !isLocal

    // The model to send for the active provider. Nothing is hardcoded: until a
    // provider's list has been fetched the saved choice is used as-is, and when
    // there is no saved choice the first model the provider offered wins.
    function activeModel() {
        if (isClaudeCode)
            return GlobalConfig.ai.defaultClaudeCodeModel || "default";
        if (isClaude)
            return GlobalConfig.ai.defaultClaudeModel || root.claudeModelsList[0] || "";
        if (isOpenaiCompat)
            return GlobalConfig.ai[root.defaultModelField(provider)] || root.openaiCompatModelList()[0] || "";
        return GlobalConfig.ai.defaultOllamaModel || root.ollamaModelsList[0] || "";
    }

    // The config field holding the saved model choice for an OpenAI-compatible provider.
    function defaultModelField(p) {
        const which = p || provider;
        if (which === "gemini")
            return "defaultGeminiModel";
        if (which === "openrouter")
            return "defaultOpenrouterModel";
        if (which === "local")
            return "defaultLocalModel";
        if (which === "opencode")
            return "defaultOpencodeModel";
        if (which === "opencode-go")
            return "defaultOpencodeGoModel";
        return "defaultOpenaiModel";
    }

    // Providers exposed in the provider selector (respecting the enable toggles).
    readonly property var providerList: {
        var l = [];
        if (GlobalConfig.ai.enableOllama)
            l.push("ollama");
        if (GlobalConfig.ai.enableLocal)
            l.push("local");
        if (GlobalConfig.ai.enableClaudeCode)
            l.push("claude-code");
        if (GlobalConfig.ai.enableClaude)
            l.push("claude");
        if (GlobalConfig.ai.enableOpenai)
            l.push("openai");
        if (GlobalConfig.ai.enableGemini)
            l.push("gemini");
        if (GlobalConfig.ai.enableOpenrouter)
            l.push("openrouter");
        if (GlobalConfig.ai.enableOpencode)
            l.push("opencode");
        if (GlobalConfig.ai.enableOpencodeGo)
            l.push("opencode-go");
        if (l.length === 0)
            l.push("ollama");
        return l;
    }

    function providerLabel(p) {
        if (p === "claude-code")
            return "Claude Code";
        if (p === "claude")
            return "Claude API";
        if (p === "local")
            return "Local server";
        if (p === "openai")
            return "ChatGPT";
        if (p === "gemini")
            return "Gemini";
        if (p === "openrouter")
            return "OpenRouter";
        if (p === "opencode")
            return "opencode Zen";
        if (p === "opencode-go")
            return "opencode Go";
        return "Ollama";
    }

    property bool isTyping: false

    property bool isThinking: false

    property string currentThoughtText: ""

    property bool isThoughtExpanded: false

    onIsTypingChanged: {
        if (isTyping) listView.positionViewAtEnd();
    }

    property bool inAgentLoop: false

    // Rate limiting. Providers answer a 429 with how long to wait, so honour that
    // instead of surfacing an error the user can only respond to by waiting anyway.
    property int rateLimitRetries: 0

    readonly property int maxRateLimitRetries: 3

    property bool onFreeTier: false   // learned from the quota metric name in a 429

    // Ticks once a second so the status line counts down rather than showing a
    // number frozen at whatever the wait started as.
    property int rateLimitSecondsLeft: 0

    // A pending retry belongs to the conversation and model it was scheduled for.
    // Without this a wait left over from a cancelled chat fires later and answers
    // a prompt the user has already moved on from — on whatever model is selected
    // by then — and those stray requests go on to trigger fresh rate limits.
    function cancelRateLimitRetry(): void {
        rateLimitRetryTimer.stop();
        rateLimitRetryTimer.retryFn = null;
        rateLimitSecondsLeft = 0;
        rateLimitRetries = 0;
    }

    Timer {
        id: rateLimitRetryTimer

        interval: 1000
        repeat: true

        property var retryFn: null

        property string forChat: ""

        property string forModel: ""
        onTriggered: {
            root.rateLimitSecondsLeft--;
            if (root.rateLimitSecondsLeft > 0) {
                root.currentActionText = qsTr("Rate limited - retrying in %1s…").arg(root.rateLimitSecondsLeft);
                return;
            }
            stop();
            if (forChat !== root.currentChatId || forModel !== root.activeModel()) {
                retryFn = null;          // the user moved on; the answer is no longer wanted
                root.currentActionText = "";
                root.isTyping = false;
                root.isThinking = false;
                root.inAgentLoop = false;
                return;
            }
            if (retryFn) { const f = retryFn; retryFn = null; f(); }
        }
    }

    // Seconds to wait, from the provider's own answer: the Retry-After header if
    // present, else the "retry in 12.3s" the message spells out. Falls back to a
    // short pause when neither is given.
    function rateLimitDelayMs(xhr) {
        const header = xhr.getResponseHeader("Retry-After");
        if (header && !isNaN(parseFloat(header)))
            return Math.ceil(parseFloat(header) * 1000) + 500;
        const m = /retry in ([0-9.]+)\s*s/i.exec(xhr.responseText || "");
        if (m)
            return Math.ceil(parseFloat(m[1]) * 1000) + 500;
        return 15000;
    }

    function shellQuote(str) {
        if (str === null || str === undefined) return "''";
        return "'" + String(str).replace(/'/g, "'\\''") + "'";
    }

    // Parse <tool_call>{...}</tool_call> blocks from model response text
    function parseTextToolCalls(text) {
        var calls = [];
        var startTag = "<tool_call>";
        var endTag = "</tool_call>";
        var pos = 0;
        while (true) {
            var start = text.indexOf(startTag, pos);
            if (start === -1) break;
            var end = text.indexOf(endTag, start);
            if (end === -1) break;
            var jsonStr = text.substring(start + startTag.length, end).trim();
            // Remove markdown code block fences if the model included them
            jsonStr = jsonStr.replace(/^```[a-zA-Z]*\n?/, "");
            jsonStr = jsonStr.replace(/```$/, "");
            jsonStr = jsonStr.trim();

            try {
                var parsed = JSON.parse(jsonStr);
                if (parsed.name) calls.push(parsed);
            } catch(e) { Logger.log("[AI] Bad tool_call JSON: " + jsonStr); }
            pos = end + endTag.length;
        }
        return calls;
    }

    // Strip all <tool_call>...</tool_call> blocks (and text after partial open tag)
    function stripToolCalls(text) {
        var startTag = "<tool_call>";
        var endTag = "</tool_call>";
        var result = text;
        // Remove complete blocks
        while (true) {
            var s = result.indexOf(startTag);
            if (s === -1) break;
            var e = result.indexOf(endTag, s);
            if (e === -1) { result = result.substring(0, s); break; }
            result = result.substring(0, s) + result.substring(e + endTag.length);
        }
        return result.replace(/\s+$/, '');
    }

    function runAgentCommand(cmd, type) {
        var commandStr = Array.isArray(cmd) ? JSON.stringify(cmd) : '["sh", "-c", ' + JSON.stringify("exec </dev/null; " + cmd) + ']';
        var processQml = "import QtQuick\n" +
                         "import Quickshell.Io\n" +
                         "Process {\n" +
                         "    id: proc\n" +
                         "    command: " + commandStr + "\n" +
                         "    property string outStr: \"\"\n" +
                         "    property string errStr: \"\"\n" +
                         "    property bool hasExited: false\n" +
                         "    property bool outFinished: false\n" +
                         "    property bool errFinished: false\n" +
                         "    function checkDone() {\n" +
                         "        if (hasExited && outFinished && errFinished) {\n" +
                         "            root.handleAgentProcessResult(" + JSON.stringify(type) + ", proc.outStr, proc.errStr, " + JSON.stringify(cmd) + ");\n" +
                         "            proc.destroy();\n" +
                         "        }\n" +
                         "    }\n" +
                         "    stdout: StdioCollector { onStreamFinished: { proc.outStr = text || \"\"; proc.outFinished = true; proc.checkDone(); } }\n" +
                         "    stderr: StdioCollector { onStreamFinished: { proc.errStr = text || \"\"; proc.errFinished = true; proc.checkDone(); } }\n" +
                         "    onExited: code => { proc.hasExited = true; proc.checkDone(); }\n" +
                         "}";
        try {
            var obj = Qt.createQmlObject(processQml, root, "agentProcess");
            obj.running = true;
        } catch(e) {
            console.error("AGENT PROCESS ERROR: " + e.message);
            console.error("FAILED QML: \n" + processQml);
        }
    }

    property int runningToolsCount: 0

    property string accumulatedToolResults: ""

    property string accumulatedToolImage: ""

    function handleAgentProcessResult(type, stdout, stderr, cmd) {
        if (type === "screenshot_take") {
            var convertCmd = `magick ${Paths.runtimeTemp("orion_screenshot.png")} -resize '1024x1024>' -quality 85 ${Paths.runtimeTemp("orion_screenshot.jpg")} && base64 ${Paths.runtimeTemp("orion_screenshot.jpg")}`;
            runAgentCommand(convertCmd, "screenshot_encode");
        } else if (type === "screenshot_encode") {
            var b64 = stdout.replace(/\n/g, "").trim();
            accumulatedToolImage = b64;
            accumulatedToolResults += "Result of take_screenshot:\nScreenshot taken. Analyze the attached image.\n\n";
            runningToolsCount--;
            checkToolsFinished();
        } else if (type.startsWith("exec_")) {
            var toolName = type.substring(5);
            var outText = stdout.trim();
            var errText = stderr.trim();
            if (!outText && !errText) {
                outText = "(Command completed with no output. If it was a background task, it has been launched successfully.)";
            }
            // Plain prose, not a pseudo-protocol dump. The old "Tool:/Command
            // executed:/Output:/Error:" framing made Gemini either imitate the
            // format back (answering with fake tool output) or refuse outright with
            // finish_reason function_call_filter: MALFORMED_FUNCTION_CALL and an
            // empty response, which looked like generation stopping dead. Echoing
            // the raw command array back at the model never helped it either.
            accumulatedToolResults += "Result of " + toolName + ":\n" + outText + (errText ? "\n\nErrors reported:\n" + errText : "") + "\n\n";
            runningToolsCount--;
            checkToolsFinished();
        }
    }

    function checkToolsFinished() {
        if (runningToolsCount <= 0) {
            var b64 = accumulatedToolImage ? accumulatedToolImage : null;
            sendPrompt(accumulatedToolResults.trim(), true, b64, "multi_tool");
        }
    }

    // ---- Claude Code provider (subscription `claude` CLI, no API key) ----

    function claudeCodeCwd() {
        return Quickshell.env("HOME") || ".";
    }

    // Resolve the `claude` binary without depending on the shell PATH (Quickshell may
    // not inherit ~/.local/bin). If the config value is left at the default "claude",
    // point at the official installer location; a custom value is used verbatim.
    function claudeCodeBinPath() {
        var b = (GlobalConfig.ai.claudeCodeBin || "claude").trim();
        if (b === "" || b === "claude") {
            var home = Quickshell.env("HOME") || "";
            if (home !== "")
                return home + "/.local/bin/claude";
            return "claude";
        }
        return b;
    }

    // ---- Claude accounts (multi-login via CLAUDE_CONFIG_DIR) ----
    // The default ~/.claude login is always present as an implicit "Default" (id "").
    // Additional accounts each get their own config dir under ~/.config/caelestia/claude/<id>.
    function claudeAccounts() {
        var list = [{ "id": "", "name": "Default", "dir": "" }];
        try {
            var parsed = JSON.parse(GlobalConfig.ai.claudeAccountsJson || "[]");
            if (Array.isArray(parsed)) {
                var home = Quickshell.env("HOME") || "";
                for (var i = 0; i < parsed.length; i++) {
                    var a = parsed[i];
                    if (a && a.id)
                        list.push({
                            "id": String(a.id),
                            "name": String(a.name || a.id),
                            "dir": home + "/.config/caelestia/claude/" + String(a.id)
                        });
                }
            }
        } catch (e) {}
        return list;
    }

    function activeClaudeAccountObj() {
        var id = GlobalConfig.ai.activeClaudeAccount || "";
        var list = claudeAccounts();
        for (var i = 0; i < list.length; i++)
            if (list[i].id === id)
                return list[i];
        return list[0];
    }

    function activeClaudeConfigDir() {
        return activeClaudeAccountObj().dir || "";
    }

    // Real display names (login email / name) read from each account's .claude.json.
    property var resolvedAccountNames: ({})

    function accountJsonPath(id) {
        var home = Quickshell.env("HOME") || "";
        if (!id || id === "")
            return home + "/.claude.json";
        return home + "/.config/caelestia/claude/" + id + "/.claude.json";
    }

    function accountLabel(id) {
        if (resolvedAccountNames[id])
            return resolvedAccountNames[id];
        var list = claudeAccounts();
        for (var i = 0; i < list.length; i++)
            if (list[i].id === id)
                return list[i].name;
        return "Default";
    }

    // One FileView per account resolves its login name from .claude.json.
    Instantiator {
        model: root.claudeAccountIds
        delegate: FileView {
            required property string modelData

            path: root.accountJsonPath(modelData)
            printErrors: false
            watchChanges: false
            onLoaded: {
                try {
                    var d = JSON.parse(text());
                    var oa = d.oauthAccount || {};
                    var nm = oa.displayName || oa.emailAddress || "";
                    if (nm) {
                        var map = root.resolvedAccountNames;
                        map[modelData] = nm;
                        root.resolvedAccountNames = Object.assign({}, map);
                    }
                } catch (e) {}
            }
        }
    }

    readonly property var claudeAccountIds: {
        var l = [];
        var a = claudeAccounts();
        for (var i = 0; i < a.length; i++)
            l.push(a[i].id);
        return l;
    }

    // Env-var line injected into the dynamically-built Process (empty for Default).
    function claudeCodeEnvSnippet() {
        var dir = activeClaudeConfigDir();
        if (dir && dir !== "")
            return "    environment: ({ \"CLAUDE_CONFIG_DIR\": " + JSON.stringify(dir) + " })\n";
        return "";
    }

    function logClaudeCodeStderr(proc, line) {
        if (!line)
            return;
        var t = line.trim();
        if (t === "")
            return;
        proc.errAcc = (proc.errAcc || "") + t + "\n";
        Logger.log("[ClaudeCode] " + t);
    }

    // Heuristic: does this CLI output indicate the Claude account isn't logged in?
    function isClaudeCodeAuthError(text) {
        if (!text)
            return false;
        var t = String(text).toLowerCase();
        return t.indexOf("login") !== -1
            || t.indexOf("log in") !== -1
            || t.indexOf("logged in") !== -1
            || t.indexOf("not authenticated") !== -1
            || t.indexOf("unauthorized") !== -1
            || t.indexOf("authentication") !== -1
            || t.indexOf("oauth") !== -1
            || t.indexOf("invalid api key") !== -1
            || t.indexOf("api key") !== -1
            || t.indexOf("expired") !== -1
            || t.indexOf("sign in") !== -1
            || t.indexOf("credentials") !== -1;
    }

    function claudeCodeAuthHint() {
        return "It appears that Claude is not logged into your account.\n\nOpen a terminal, run the command `claude`, and log in with your subscription, then try again here.";
    }

    // Generate a short chat title via a one-shot `claude -p ... --output-format json`.
    function generateClaudeCodeTitleAsync(chatId, firstMessage) {
        if (!firstMessage)
            return;
        var safeMsg = firstMessage.substring(0, 200);
        var prompt = "Output ONLY a concise 2-4 word title for the following message. No quotes, no trailing punctuation, no explanation.\n\nMessage: " + safeMsg;

        var cmd = [claudeCodeBinPath(), "-p", prompt, "--output-format", "json", "--dangerously-skip-permissions"];
        var commandStr = JSON.stringify(cmd);
        var cwdStr = JSON.stringify(claudeCodeCwd());
        var chatIdStr = JSON.stringify(chatId);
        var qml =
            "import QtQuick\n" +
            "import Quickshell.Io\n" +
            "Process {\n" +
            "    id: tproc\n" +
            "    command: " + commandStr + "\n" +
            "    workingDirectory: " + cwdStr + "\n" +
            claudeCodeEnvSnippet() +
            "    stdout: StdioCollector { onStreamFinished: root.handleClaudeCodeTitle(" + chatIdStr + ", text || \"\", tproc); }\n" +
            "    onExited: code => { if (code !== 0) tproc.destroy(); }\n" +
            "}";
        try {
            var obj = Qt.createQmlObject(qml, root, "claudeCodeTitleProc");
            obj.running = true;
        } catch (e) {
            Logger.log("[AI] claude-code title process error: " + e.message);
        }
    }

    function handleClaudeCodeTitle(chatId, text, proc) {
        try {
            var parsed = JSON.parse(text);
            if (parsed && parsed.result && !parsed.is_error)
                applyGeneratedTitle(chatId, String(parsed.result));
        } catch (e) {}
        if (proc)
            proc.destroy();
    }

    function stopClaudeCode() {
        if (root.currentClaudeCodeProc) {
            try {
                root.currentClaudeCodeProc.running = false;
            } catch (e) {}
            root.currentClaudeCodeProc = null;
        }
    }

    function sendClaudeCode(promptText) {
        // Drop any stale empty assistant placeholder, then add a fresh bubble to stream into.
        for (var i = chatHistory.count - 1; i >= 0; i--) {
            var m = chatHistory.get(i);
            if (!m.isUser && !m.isFinished && m.text === "")
                chatHistory.remove(i);
        }
        chatHistory.append({
            "isUser": false,
            "text": "",
            "isFinished": false,
            "thoughtText": ""
        });
        listView.positionViewAtEnd();

        var bin = claudeCodeBinPath();
        var sid = claudeCodeSessionFor(currentChatId);

        // Fresh session (new chat, or the active account changed) → seed it with the
        // prior transcript so the new account continues the same conversation.
        var promptToSend = promptText;
        if (sid === "") {
            var transcript = claudeCodeTranscript();
            if (transcript !== "")
                promptToSend = transcript;
        }

        var cmd = [bin, "-p", promptToSend, "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--dangerously-skip-permissions"];

        var mdl = GlobalConfig.ai.defaultClaudeCodeModel || "default";
        if (mdl && mdl !== "default") {
            cmd.push("--model");
            cmd.push(mdl);
        }

        var eff = GlobalConfig.ai.claudeCodeEffort || "default";
        if (eff && eff !== "default" && effortLevelsFor(mdl).indexOf(eff) !== -1) {
            cmd.push("--effort");
            cmd.push(eff);
        }

        if (sid !== "") {
            cmd.push("--resume");
            cmd.push(sid);
        }

        var commandStr = JSON.stringify(cmd);
        var cwdStr = JSON.stringify(claudeCodeCwd());
        var processQml =
            "import QtQuick\n" +
            "import Quickshell.Io\n" +
            "Process {\n" +
            "    id: proc\n" +
            "    command: " + commandStr + "\n" +
            "    workingDirectory: " + cwdStr + "\n" +
            claudeCodeEnvSnippet() +
            "    property string acc: \"\"\n" +
            "    property string thought: \"\"\n" +
            "    property string sess: \"\"\n" +
            "    property string errAcc: \"\"\n" +
            "    property bool done: false\n" +
            "    stdout: SplitParser { onRead: line => root.onClaudeCodeLine(proc, line) }\n" +
            "    stderr: SplitParser { onRead: line => root.logClaudeCodeStderr(proc, line) }\n" +
            "    onExited: code => root.onClaudeCodeExit(proc, code)\n" +
            "}";
        try {
            var obj = Qt.createQmlObject(processQml, root, "claudeCodeProc");
            root.currentClaudeCodeProc = obj;
            obj.running = true;
        } catch (e) {
            console.error("CLAUDE CODE PROCESS ERROR: " + e.message);
            chatHistory.setProperty(chatHistory.count - 1, "text", "⚠️ Failed to launch Claude Code: " + e.message);
            chatHistory.setProperty(chatHistory.count - 1, "isFinished", true);
            isTyping = false;
            isThinking = false;
            inAgentLoop = false;
            saveHistory();
        }
    }

    function onClaudeCodeLine(proc, line) {
        line = (line || "").trim();
        if (line === "")
            return;

        var evt;
        try {
            evt = JSON.parse(line);
        } catch (e) {
            return; // non-JSON diagnostic output
        }

        if (evt.session_id)
            proc.sess = evt.session_id;

        if (evt.type === "system")
            return;

        // Token-level streaming (when the CLI emits partial messages).
        if (evt.type === "stream_event" && evt.event) {
            var ev = evt.event;
            if (ev.type === "content_block_delta" && ev.delta) {
                if (ev.delta.type === "text_delta") {
                    proc.acc += ev.delta.text || "";
                    if (isThinking) isThinking = false;
                } else if (ev.delta.type === "thinking_delta") {
                    proc.thought += ev.delta.thinking || "";
                }
                root.currentThoughtText = proc.thought.trim();
                chatHistory.setProperty(chatHistory.count - 1, "thoughtText", proc.thought.trim());
                chatHistory.setProperty(chatHistory.count - 1, "text", proc.acc.trim());
                listView.positionViewAtEnd();
            }
            return;
        }

        // Whole assistant messages (also carry tool_use blocks). Used as the fallback
        // when token-level partials aren't emitted, and to surface tool activity.
        if (evt.type === "assistant" && evt.message && evt.message.content) {
            var hasTool = false;
            var textPart = "";
            for (var i = 0; i < evt.message.content.length; i++) {
                var b = evt.message.content[i];
                if (b.type === "tool_use") {
                    hasTool = true;
                    if (b.name)
                        currentActionText = "Running " + b.name + "...";
                } else if (b.type === "text") {
                    textPart += b.text || "";
                }
            }
            if (textPart.trim() !== "" && proc.acc.indexOf(textPart) === -1) {
                proc.acc = (proc.acc ? proc.acc + "\n\n" : "") + textPart;
                if (isThinking) isThinking = false;
                chatHistory.setProperty(chatHistory.count - 1, "text", proc.acc.trim());
                listView.positionViewAtEnd();
            }
            if (hasTool && textPart.trim() === "")
                isThinking = true;
            return;
        }

        if (evt.type === "result") {
            var resText = (evt.result !== undefined && evt.result !== null) ? String(evt.result) : "";
            var errored = (evt.is_error === true) || (evt.subtype && String(evt.subtype).indexOf("error") !== -1);
            if (errored && (isClaudeCodeAuthError(resText) || isClaudeCodeAuthError(proc.errAcc))) {
                proc.acc = claudeCodeAuthHint();
            } else if (proc.acc.trim() === "" && resText !== "") {
                proc.acc = resText;
            }
            finalizeClaudeCode(proc);
            return;
        }
    }

    function finalizeClaudeCode(proc) {
        if (proc.done)
            return;
        proc.done = true;
        var finalText = (proc.acc || "").trim();
        chatHistory.setProperty(chatHistory.count - 1, "text", finalText !== "" ? finalText : "(no output)");
        chatHistory.setProperty(chatHistory.count - 1, "isFinished", true);
        setClaudeCodeSession(currentChatId, proc.sess);
        isTyping = false;
        isThinking = false;
        inAgentLoop = false;
        currentActionText = "Thinking...";
        saveHistory();
        listView.positionViewAtEnd();
    }

    function onClaudeCodeExit(proc, code) {
        if (!proc.done) {
            if ((proc.acc || "").trim() === "") {
                if (isClaudeCodeAuthError(proc.errAcc))
                    chatHistory.setProperty(chatHistory.count - 1, "text", claudeCodeAuthHint());
                else if (code !== 0)
                    chatHistory.setProperty(chatHistory.count - 1, "text",
                        "⚠️ Claude Code çalıştırılamadı (çıkış kodu " + code + "). `claude` CLI kurulu ve giriş yapılmış mı? Bir terminalde `claude` çalıştırıp giriş yapmayı deneyin.");
            }
            finalizeClaudeCode(proc);
        }
        if (root.currentClaudeCodeProc === proc)
            root.currentClaudeCodeProc = null;
        proc.destroy();
    }

    property string currentActionText: "Thinking..."

    function fetchOllamaModels() {
        var ollamaUrl = GlobalConfig.ai.ollamaUrl || "http://localhost:11434";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ollamaUrl + "/api/tags", true);
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        var list = [];
                        if (response.models) {
                            for (var i = 0; i < response.models.length; i++) {
                                list.push(response.models[i].name);
                            }
                        }
                        // Only what this Ollama instance actually has pulled — a
                        // guessed list would just offer models that aren't installed.
                        ollamaModelsList = list;
                        if (list.length > 0 && list.indexOf(GlobalConfig.ai.defaultOllamaModel) === -1)
                            GlobalConfig.ai.defaultOllamaModel = list[0];
                    } catch (e) {
                        Logger.log("Error parsing Ollama models: " + e.message);
                    }
                } else {
                    Logger.log("Ollama tags request failed (status " + xhr.status + ")");
                }
            }
        };
        xhr.onerror = () => { root.logFetchError("Ollama"); };
        xhr.send();
    }

    // Models offered by the OpenAI-compatible providers, keyed by provider id.
    // Fetched from /models on demand; the fallbacks below are used until a fetch
    // succeeds (and when it can't, e.g. no key yet).
    property var openaiCompatModels: ({})

    function openaiCompatModelList(p) {
        return root.openaiCompatModels[p || provider] || [];
    }

    // Providers charge a request for their model list too, and on a free tier that
    // is quota the user would rather spend on answers — so fetch each provider's
    // list once per session instead of every time the sidebar opens.
    property var modelsFetched: ({})

    function fetchOpenaiCompatModels(p, force = false) {
        const which = p || provider;
        if (!force && root.modelsFetched[which])
            return;
        const key = root.getApiKeyFor(which);
        // OpenRouter and opencode publish their catalogues without auth; the rest
        // need the key. A local server is unauthenticated by definition.
        const publicCatalogue = which === "openrouter" || which === "opencode" || which === "opencode-go" || which === "local";
        if (key === "" && !publicCatalogue)
            return;

        var xhr = new XMLHttpRequest();
        xhr.open("GET", root.openaiCompatBase(which) + "/models", true);
        if (key !== "")
            root.setAuthHeader(xhr, which);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                Logger.log("[AI] " + root.providerLabel(which) + " model list failed (status " + xhr.status + ")");
                return;
            }
            try {
                const parsed = JSON.parse(xhr.responseText);
                var list = [];
                for (var i = 0; i < (parsed.data || []).length; i++) {
                    const id = parsed.data[i].id;
                    if (!id)
                        continue;
                    // Gemini prefixes ids with "models/"; the chat endpoint accepts either,
                    // but the bare id is what users recognise.
                    list.push(id.indexOf("models/") === 0 ? id.substring(7) : id);
                }
                // Only chat-capable models are useful here — drop embedding/audio/image
                // ones. A local server is exempt: its list is the user's own model
                // files, so a filename that happens to contain "image" or "vision"
                // is still the one model they chose to serve.
                if (which !== "local")
                    list = list.filter(m => !/embed|whisper|tts|audio|image|vision-preview|moderation|rerank|dall-e/i.test(m));
                // opencode lists models the shell has no wire format for; offering them
                // would only produce a failed send once the user picked one.
                if (which === "opencode" || which === "opencode-go")
                    list = list.filter(m => root.opencodeSupports(which, m));
                list.sort();
                if (list.length === 0)
                    return;
                var next = {};
                for (var k in root.openaiCompatModels)
                    next[k] = root.openaiCompatModels[k];
                next[which] = list;
                root.openaiCompatModels = next;

                const seen = root.modelsFetched;
                seen[which] = true;
                root.modelsFetched = seen;

                // Keep the saved default honest: if it isn't offered, fall back to the first.
                const cfgKey = root.defaultModelField(which);
                if (list.indexOf(GlobalConfig.ai[cfgKey]) === -1)
                    GlobalConfig.ai[cfgKey] = list[0];
            } catch (e) {
                Logger.log("[AI] Error parsing " + root.providerLabel(which) + " models: " + e.message);
            }
        };
        xhr.onerror = () => { root.logFetchError(which); };
        xhr.send();
    }

    property var allChatSessions: []

    function createNewChat() {
        cancelRateLimitRetry();
        typingTimer.stop();
        stopClaudeCode();
        isTyping = false;
        isThinking = false;
        inAgentLoop = false;
        currentChatId = "chat_" + Date.now();
        chatHistory.clear();
        isHistoryTab = false;
    }

    function loadChat(id) {
        cancelRateLimitRetry();
        typingTimer.stop();
        stopClaudeCode();
        isTyping = false;
        isThinking = false;
        inAgentLoop = false;
        currentChatId = id;
        chatHistory.clear();
        var found = false;
        for (var i = 0; i < allChatSessions.length; i++) {
            if (allChatSessions[i].id === id) {
                var msgs = allChatSessions[i].messages;
                for (var j = 0; j < msgs.length; j++) {
                    // Strictly sanitize incoming JSON data before ListModel append
                    chatHistory.append({
                        "isUser": msgs[j].isUser === true,
                        "text": msgs[j].text || "",
                        "isFinished": msgs[j].isFinished !== false,
                        "thoughtText": msgs[j].thoughtText || ""
                    });
                }
                found = true;
                break;
            }
        }
        if (!found) createNewChat();
        savedContentY = -1;
        Qt.callLater(function() { listView.positionViewAtEnd(); });
        isHistoryTab = false;
    }

    function loadHistory() {
        allChatSessions = [];
        var jsonStr = GlobalConfig.ai.ollamaHistoryJson;
        if (jsonStr) {
            try {
                var parsed = JSON.parse(jsonStr);
                // Protect against corrupted saves
                if (Array.isArray(parsed)) {
                    allChatSessions = parsed.filter(s => s !== null && s.id);
                }
            } catch (e) {}
        }

        historySessionsModel.clear();
        for (var i = 0; i < allChatSessions.length; i++) {
            // Strictly enforce string values
            historySessionsModel.append({
                "id": allChatSessions[i].id || ("chat_" + Date.now()),
                "title": allChatSessions[i].title || "Chat"
            });
        }

        if (allChatSessions.length > 0) {
            loadChat(allChatSessions[0].id);
        } else {
            createNewChat();
        }
    }

    function saveHistory() {
        var msgs = [];
        for (var i = 0; i < chatHistory.count; i++) {
            var msg = chatHistory.get(i);
            msgs.push({
                "isUser": msg.isUser === true,
                "text": msg.text || "",
                "isFinished": msg.isFinished !== false,
                "thoughtText": msg.thoughtText || ""
            });
        }
        
        if (msgs.length === 0) return;
        
        var found = false;
        for (var j = 0; j < allChatSessions.length; j++) {
            if (allChatSessions[j].id === currentChatId) {
                allChatSessions[j].messages = msgs;
                
                var firstUser = null;
                for (var k = 0; k < msgs.length; k++) {
                    if (msgs[k].isUser) { firstUser = msgs[k]; break; }
                }
                if (msgs.length > 1 && (allChatSessions[j].title === "Legacy Chat" || allChatSessions[j].title === "New Chat" || allChatSessions[j].title.indexOf("New Chat") === 0 || !allChatSessions[j].title)) {
                    if (firstUser) {
                        generateChatTitleAsync(currentChatId, firstUser.text);
                    }
                }
                found = true;
                break;
            }
        }
        
        if (!found) {
            var firstUserMsg = null;
            for (var m = 0; m < msgs.length; m++) {
                if (msgs[m].isUser) { firstUserMsg = msgs[m]; break; }
            }
            
            var initialTitle = "New Chat";
            
            allChatSessions.unshift({
                "id": currentChatId || ("chat_" + Date.now()),
                "title": initialTitle,
                "messages": msgs
            });
            
            historySessionsModel.insert(0, {
                "id": currentChatId || ("chat_" + Date.now()),
                "title": initialTitle
            });
            
            if (firstUserMsg) {
                generateChatTitleAsync(currentChatId, firstUserMsg.text);
            }
        }
        
        GlobalConfig.ai.ollamaHistoryJson = JSON.stringify(allChatSessions);
    }

    function deleteChat(id) {
        cancelRateLimitRetry();
        var idx = -1;
        for (var i = 0; i < allChatSessions.length; i++) {
            if (allChatSessions[i].id === id) {
                idx = i;
                break;
            }
        }
        if (idx !== -1) {
            allChatSessions.splice(idx, 1);
            for (var j = 0; j < historySessionsModel.count; j++) {
                if (historySessionsModel.get(j).id === id) {
                    historySessionsModel.remove(j);
                    break;
                }
            }
            
            GlobalConfig.ai.ollamaHistoryJson = JSON.stringify(allChatSessions);

            if (currentChatId === id) {
                chatHistory.clear();
                if (allChatSessions.length > 0) {
                    loadChat(allChatSessions[0].id);
                } else {
                    createNewChat();
                }
            }
        }
    }

    function clearAllHistory() {
        cancelRateLimitRetry();
        allChatSessions = [];
        historySessionsModel.clear();
        GlobalConfig.ai.ollamaHistoryJson = "[]";
        createNewChat();
    }

    function applyGeneratedTitle(chatId, raw) {
        if (!raw)
            return;
        var title = raw.trim().replace(/^"|"$/g, '').replace(/\n/g, ' ');
        if (title.length > 40)
            title = title.substring(0, 40) + "...";
        if (title.length > 0)
            updateChatTitle(chatId, title);
    }

    function generateChatTitleAsync(chatId, firstMessage) {
        if (!firstMessage) return;

        if (root.isClaudeCode) {
            root.generateClaudeCodeTitleAsync(chatId, firstMessage);
            return;
        }

        var safeMsg = firstMessage.substring(0, 200);
        var titleSystem = "You are a title generator. Output ONLY a 2-4 word title representing the user's message. NO quotes, NO explanation.";
        var xhr = new XMLHttpRequest();

        if (root.isClaude) {
            if (root.getApiKey() === "")
                return;
            var claudeBase = GlobalConfig.ai.anthropicUrl || "https://api.anthropic.com";
            xhr.open("POST", claudeBase + "/v1/messages", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("x-api-key", root.getApiKey());
            xhr.setRequestHeader("anthropic-version", "2023-06-01");
            xhr.setRequestHeader("anthropic-dangerous-direct-browser-access", "true");
            xhr.onreadystatechange = () => {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try {
                        var parsed = JSON.parse(xhr.responseText);
                        if (parsed.content && parsed.content.length > 0 && parsed.content[0].text)
                            root.applyGeneratedTitle(chatId, parsed.content[0].text);
                    } catch (e) {}
                }
            };
            xhr.onerror = () => {};
            xhr.send(JSON.stringify({
                model: root.activeModel(),
                max_tokens: 32,
                system: titleSystem,
                messages: [{ role: "user", content: "Message: " + safeMsg + "\nTitle:" }]
            }));
            return;
        }

        if (root.isOpenaiCompat) {
            if (root.getApiKey() === "")
                return;
            // Same per-model wire split as sendPrompt — an opencode model on /messages
            // needs the Anthropic shape here too.
            const useAnthropic = root.anthropicWire;
            xhr.open("POST", root.openaiCompatBase() + (useAnthropic ? "/messages" : "/chat/completions"), true);
            xhr.setRequestHeader("Content-Type", "application/json");
            root.setAuthHeader(xhr);
            if (useAnthropic)
                xhr.setRequestHeader("anthropic-version", "2023-06-01");
            xhr.onreadystatechange = () => {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try {
                        var oaiParsed = JSON.parse(xhr.responseText);
                        if (useAnthropic) {
                            if (oaiParsed.content && oaiParsed.content.length > 0 && oaiParsed.content[0].text)
                                root.applyGeneratedTitle(chatId, oaiParsed.content[0].text);
                        } else if (oaiParsed.choices && oaiParsed.choices.length > 0 && oaiParsed.choices[0].message) {
                            root.applyGeneratedTitle(chatId, oaiParsed.choices[0].message.content || "");
                        }
                    } catch (e) {}
                }
            };
            xhr.onerror = () => {};
            xhr.send(JSON.stringify(useAnthropic ? {
                model: root.activeModel(),
                max_tokens: 32,
                system: titleSystem,
                messages: [{ role: "user", content: "Message: " + safeMsg + "\nTitle:" }]
            } : {
                model: root.activeModel(),
                messages: [
                    { role: "system", content: titleSystem },
                    { role: "user", content: "Message: " + safeMsg + "\nTitle:" }
                ],
                stream: false
            }));
            return;
        }

        var url = (GlobalConfig.ai.ollamaUrl || "http://localhost:11434") + "/api/generate";
        xhr.open("POST", url, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var parsed = JSON.parse(xhr.responseText);
                    if (parsed.response)
                        root.applyGeneratedTitle(chatId, parsed.response);
                } catch (e) {}
            }
        };
        xhr.onerror = () => {};
        xhr.send(JSON.stringify({
            model: GlobalConfig.ai.defaultOllamaModel || "llama3",
            system: titleSystem,
            prompt: "Message: " + safeMsg + "\nTitle:",
            stream: false
        }));
    }

    function updateChatTitle(chatId, title) {
        if (!title || !chatId) return;
        
        for (var i = 0; i < allChatSessions.length; i++) {
            if (allChatSessions[i].id === chatId) {
                allChatSessions[i].title = title;
                
                var inModel = false;
                for (var j = 0; j < historySessionsModel.count; j++) {
                    if (historySessionsModel.get(j).id === chatId) {
                        historySessionsModel.setProperty(j, "title", title);
                        inModel = true;
                        break;
                    }
                }
                
                if (!inModel) {
                    historySessionsModel.insert(0, {
                        "id": chatId || "",
                        "title": title || "New Chat"
                    });
                }
                
                GlobalConfig.ai.ollamaHistoryJson = JSON.stringify(allChatSessions);
                break;
            }
        }
    }

    function addAiMessage(message) {
        chatHistory.append({
            "isUser": false,
            "text": message || "",
            "isFinished": true,
            "thoughtText": ""
        });
        listView.positionViewAtEnd();
        saveHistory();
    }

    function sendPrompt(promptText, isSystemToolResult = false, base64Image = null, toolName = "", isRetry = false) {
        if (!promptText.trim() && !base64Image) return;

        // Sending a message dismisses any open prompt suggestions.
        promptSuggestions = [];

        if (!isRetry)
            cancelRateLimitRetry();   // a new send supersedes any wait still pending

        if (!isSystemToolResult && !isRetry) {
            chatHistory.append({
                "isUser": true,
                "text": promptText || "",
                "isFinished": true,
                "thoughtText": ""
            });
            listView.positionViewAtEnd();
            saveHistory();
        }

        if (root.needsApiKey && root.getApiKey() === "") {
            const envNames = {
                "claude": "ANTHROPIC_API_KEY",
                "openai": "OPENAI_API_KEY",
                "gemini": "GEMINI_API_KEY",
                "openrouter": "OPENROUTER_API_KEY",
                "opencode": "OPENCODE_API_KEY",
                "opencode-go": "OPENCODE_API_KEY"
            };
            addAiMessage("⚠️ No " + root.providerLabel(root.provider) + " API key configured. Set the "
                + (envNames[root.provider] || "API") + " environment variable, or add a key in the AI settings.");
            return;
        }

        isTyping = true;
        isThinking = true;
        inAgentLoop = true;
        currentThoughtText = "";
        isThoughtExpanded = false;
        
        if (isSystemToolResult) {
            if (toolName === "web_search" || toolName === "read_webpage") {
                currentActionText = "Reading results...";
            } else if (toolName === "take_screenshot") {
                currentActionText = "Analyzing screen...";
            } else if (toolName === "get_weather") {
                currentActionText = "Analyzing weather...";
            } else {
                currentActionText = "Thinking...";
            }
        } else {
            currentActionText = "Thinking...";
        }

        // Claude Code (subscription CLI) uses a Process, not XMLHttpRequest.
        if (root.isClaudeCode) {
            root.sendClaudeCode(promptText);
            return;
        }

        var xhr = new XMLHttpRequest();
        root.currentRequest = xhr;

        var model = root.activeModel();
        // Anthropic Messages vs OpenAI chat completions is a property of the model on
        // opencode, not of the provider, so the endpoint, body and stream parsing all
        // key off this rather than off isClaude.
        const useAnthropic = root.anthropicWire;
        if (root.isClaude) {
            var claudeBase = GlobalConfig.ai.anthropicUrl || "https://api.anthropic.com";
            xhr.open("POST", claudeBase + "/v1/messages", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("x-api-key", root.getApiKey());
            xhr.setRequestHeader("anthropic-version", "2023-06-01");
            // QML's XMLHttpRequest presents a browser-like origin; this header opts into direct access.
            xhr.setRequestHeader("anthropic-dangerous-direct-browser-access", "true");
        } else if (root.isOpenaiCompat) {
            xhr.open("POST", root.openaiCompatBase() + (useAnthropic ? "/messages" : "/chat/completions"), true);
            xhr.setRequestHeader("Content-Type", "application/json");
            root.setAuthHeader(xhr);
            if (useAnthropic)
                xhr.setRequestHeader("anthropic-version", "2023-06-01");
            if (root.provider === "openrouter") {
                // OpenRouter attributes requests to an app via these; harmless elsewhere.
                xhr.setRequestHeader("HTTP-Referer", "https://github.com/ladybug-me/caelestia-kde");
                xhr.setRequestHeader("X-Title", "Caelestia Shell");
            }
        } else {
            var ollamaUrl = GlobalConfig.ai.ollamaUrl || "http://localhost:11434";
            xhr.open("POST", ollamaUrl + "/api/chat", true);
            xhr.setRequestHeader("Content-Type", "application/json");
        }
        
        var processedTextLength = 0;
        var accumulatedThoughtText = "";
        var accumulatedContentText = "";
        var rawAccumulatedContentText = "";
        var finalToolCalls = null;
        
        for (var i = chatHistory.count - 1; i >= 0; i--) {
            var m = chatHistory.get(i);
            if (!m.isUser && !m.isFinished && m.text === "") {
                chatHistory.remove(i);
            }
        }
        
        chatHistory.append({
            "isUser": false,
            "text": "",
            "isFinished": false,
            "thoughtText": ""
        });
        
        listView.positionViewAtEnd();
        
        xhr.onerror = () => { root.handleSendError(); };
        xhr.onreadystatechange = () => {
            if (xhr.readyState === 3 || xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var currentText = xhr.responseText;
                    var unparsed = currentText.substring(processedTextLength);
                    var lines = unparsed.split('\n');
                    
                    var linesToProcess = (xhr.readyState === XMLHttpRequest.DONE) ? lines.length : lines.length - 1;
                    
                    for (var i = 0; i < linesToProcess; i++) {
                        var rawLine = lines[i];
                        var line = rawLine.trim();
                        if (line === "") {
                            processedTextLength += rawLine.length + 1;
                            continue;
                        }

                        var chunkContent = "";
                        var chunkReasoning = "";

                        if (useAnthropic) {
                            // Anthropic streams Server-Sent Events; only "data:" lines carry JSON.
                            if (line.indexOf("event:") === 0) {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            if (line.indexOf("data:") !== 0) {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            var jsonStr = line.substring(5).trim();
                            if (jsonStr === "" || jsonStr === "[DONE]") {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            try {
                                var evt = JSON.parse(jsonStr);
                                processedTextLength += rawLine.length + 1;
                                if (evt.type === "content_block_delta" && evt.delta) {
                                    if (evt.delta.type === "text_delta")
                                        chunkContent = evt.delta.text || "";
                                    else if (evt.delta.type === "thinking_delta")
                                        chunkReasoning = evt.delta.thinking || "";
                                } else if (evt.type === "error") {
                                    Logger.log("[AI] Claude stream error: " + JSON.stringify(evt.error || {}));
                                }
                            } catch (e) {
                                break;
                            }
                        } else if (root.isOpenaiCompat) {
                            // OpenAI-compatible streaming: SSE where each "data:" line is a
                            // chunk holding choices[0].delta. "[DONE]" ends the stream.
                            if (line.indexOf("data:") !== 0) {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            var oaiJson = line.substring(5).trim();
                            if (oaiJson === "" || oaiJson === "[DONE]") {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            try {
                                var oaiEvt = JSON.parse(oaiJson);
                                processedTextLength += rawLine.length + 1;
                                if (oaiEvt.error) {
                                    Logger.log("[AI] " + root.providerLabel(root.provider) + " stream error: " + JSON.stringify(oaiEvt.error));
                                } else if (oaiEvt.choices && oaiEvt.choices.length > 0) {
                                    var delta = oaiEvt.choices[0].delta || {};
                                    chunkContent = delta.content || "";
                                    // Reasoning models expose their thinking under different
                                    // keys depending on the provider.
                                    chunkReasoning = delta.reasoning_content || delta.reasoning || "";
                                }
                            } catch (e) {
                                break;
                            }
                        } else {
                            // Ollama streams newline-delimited JSON objects.
                            try {
                                var parsed = JSON.parse(line);
                                processedTextLength += rawLine.length + 1;
                                if (parsed.message) {
                                    chunkReasoning = parsed.message.thinking || parsed.message.reasoning || parsed.message.reasoning_content || "";
                                    chunkContent = parsed.message.content || "";
                                }
                            } catch (e) {
                                break;
                            }
                        }

                        if (chunkReasoning)
                            accumulatedThoughtText += chunkReasoning;
                        if (chunkContent)
                            rawAccumulatedContentText += chunkContent;

                        if (chunkContent === "" && chunkReasoning === "")
                            continue;

                        var displayContent = stripToolCalls(rawAccumulatedContentText);
                        var displayThought = accumulatedThoughtText;

                        if (accumulatedThoughtText === "") {
                            var openThinkIdx = displayContent.indexOf("<think>");
                            var closeThinkIdx = displayContent.indexOf("</think>");

                            if (openThinkIdx !== -1) {
                                if (closeThinkIdx !== -1) {
                                    displayThought = displayContent.substring(openThinkIdx + 7, closeThinkIdx).trim();
                                    displayContent = displayContent.substring(0, openThinkIdx) + displayContent.substring(closeThinkIdx + 8);
                                } else {
                                    displayThought = displayContent.substring(openThinkIdx + 7).trim();
                                    displayContent = displayContent.substring(0, openThinkIdx);
                                }
                            }
                        }

                        root.currentThoughtText = displayThought.trim();

                        if (displayContent.trim() !== "") {
                            if (isThinking) isThinking = false;
                        }

                        chatHistory.setProperty(chatHistory.count - 1, "thoughtText", displayThought.trim());
                        chatHistory.setProperty(chatHistory.count - 1, "text", displayContent.trim());
                        listView.positionViewAtEnd();
                    }
                }
                
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                            root.rateLimitRetries = 0;
                    chatHistory.setProperty(chatHistory.count - 1, "isFinished", true);
                        saveHistory();
                        
                        var enableTools = GlobalConfig.ai.enableCelestialMode;
                        var textToolCalls = enableTools ? parseTextToolCalls(rawAccumulatedContentText) : [];

                        if (textToolCalls.length > 0) {
                            if (enableTools) {
                                currentActionText = "Using tools...";
                                accumulatedToolResults = "";
                                accumulatedToolImage = "";
                                runningToolsCount = 0;

                                for (var t = 0; t < textToolCalls.length; t++) {
                                    var toolCall = textToolCalls[t];
                                    var toolName = toolCall.name;
                                    var args = toolCall.args || {};

                                    // Count async tools (set_timer and get_weather are synchronous, skip count for them)
                                    if (toolName === "take_screenshot" || toolName === "web_search" || toolName === "read_webpage" || toolName === "open_app" || toolName === "caelestia_command") {
                                        runningToolsCount++;
                                    }

                                    if (toolName === "take_screenshot") {
                                        currentActionText = "Analyzing screen...";
                                        var screenCmd = `spectacle -b -m -n -o ${Paths.runtimeTemp("orion_screenshot.png")}`;
                                        runAgentCommand(screenCmd, "screenshot_take");

                                    } else if (toolName === "web_search") {
                                        currentActionText = "Searching the web...";
                                        var query = String(args.query || "");
                                        var page = args.page || 1;
                                        runAgentCommand(["env", "PYTHONIOENCODING=utf8", "python3", Quickshell.shellDir + "/scripts/orion_search.py", "--mode", "search", "--query", query, "--page", String(page)], "exec_" + toolName);

                                    } else if (toolName === "read_webpage") {
                                        currentActionText = "Reading webpage...";
                                        var url = String(args.url || "");
                                        runAgentCommand(["env", "PYTHONIOENCODING=utf8", "python3", Quickshell.shellDir + "/scripts/orion_search.py", "--mode", "read", "--url", url], "exec_" + toolName);

                                    } else if (toolName === "open_app") {
                                        currentActionText = "Opening app...";
                                        var app = String(args.app_name || "");
                                        var safeApp = shellQuote("Name=.*" + app);
                                        runAgentCommand(["sh", "-c", 'grep -i -m 1 "^Exec=" $(find /usr/share/applications ~/.local/share/applications -name "*.desktop" -exec grep -il "$1" {} + 2>/dev/null) | cut -d "=" -f 2- | sed "s/ %[a-zA-Z]//g" | xargs -I {} sh -c "setsid {} >/dev/null 2>&1 &"', "--", safeApp], "exec_" + toolName);

                                    } else if (toolName === "set_timer") {
                                        currentActionText = "Setting timer...";
                                        var secs = Number(args.seconds) || 5;
                                        var msg = String(args.message || "Timer finished");
                                        var timerQml = "import QtQuick; Timer { interval: " + (secs * 1000) + "; running: true; onTriggered: { root.runAgentCommand(['notify-send', 'Orion Timer', " + JSON.stringify(msg) + "], 'timer_trigger'); destroy(); } }";
                                        Qt.createQmlObject(timerQml, root, "timer_" + Date.now());
                                        accumulatedToolResults += "Tool: set_timer\nResult: Timer set for " + secs + " seconds with message: " + msg + "\n\n";

                                    } else if (toolName === "get_weather") {
                                        currentActionText = "Checking weather...";
                                        var weatherStr = Weather.city + ": " + Weather.temp + " (" + Weather.description + "). Humidity: " + Weather.humidity + "%, Wind: " + Weather.windSpeed + " km/h";
                                        accumulatedToolResults += "Tool: get_weather\nResult: Local weather from system dashboard: " + weatherStr + "\n\n";

                                    } else if (toolName === "caelestia_command") {
                                        currentActionText = "Running caelestia...";
                                        var subcmd = String(args.subcommand || "");
                                        var subargs = String(args.args || "").trim();
                                        var cmdArr = ["caelestia", subcmd];
                                        if (subargs) cmdArr = cmdArr.concat(subargs.split(/\s+/));
                                        runAgentCommand(cmdArr, "exec_" + toolName);

                                    } else {
                                        Logger.log("[AI] Unknown tool: " + toolName);
                                        runningToolsCount--; // don't block on unknown tools
                                    }
                                }

                                // set_timer is synchronous — check if all async tools are already done
                                if (runningToolsCount === 0) {
                                    if (accumulatedToolResults !== "") {
                                        checkToolsFinished();
                                    } else {
                                        currentActionText = "Thinking...";
                                        isTyping = false;
                                        isThinking = false;
                                        inAgentLoop = false;
                                    }
                                }
                            } else {
                                currentActionText = "Thinking...";
                                isTyping = false;
                                isThinking = false;
                                inAgentLoop = false;
                            }
                        } else {
                            currentActionText = "Thinking...";
                            isTyping = false;
                            isThinking = false;
                            inAgentLoop = false;
                        }
                    } else {
                        var providerName = root.providerLabel(root.provider);
                        // Providers explain themselves in the error body — a rate limit
                        // even says how long to wait. Surfacing that beats a bare status
                        // code the user can do nothing with.
                        var apiDetail = "";
                        try {
                            const errBody = JSON.parse(xhr.responseText);
                            const e = Array.isArray(errBody) ? (errBody[0] || {}).error : errBody.error;
                            if (e) {
                                // OpenRouter wraps the upstream provider's error: its own
                                // message is just "Provider returned error", and the part
                                // worth reading (which model, which provider, what to do)
                                // sits in metadata.raw.
                                const raw = e.metadata && e.metadata.raw ? String(e.metadata.raw) : "";
                                const provider = e.metadata && e.metadata.provider_name ? String(e.metadata.provider_name) : "";
                                if (raw)
                                    apiDetail = " " + (provider ? provider + ": " : "") + raw.split("\n")[0];
                                else if (e.message)
                                    apiDetail = " " + String(e.message).split("\n")[0];
                            }
                        } catch (e) {}
                        // A rate limit is not really a failure — the provider told us
                        // when it will accept the next request, so wait that long and
                        // finish the answer instead of dropping it on the user.
                        // A daily quota does not come back in the seconds the provider
                        // suggests retrying after, so retrying just spends more of the
                        // very allowance that ran out. Only wait out short-term limits.
                        const perDayQuota = /PerDay|per day/i.test(xhr.responseText || "");
                        if (xhr.status === 429 && perDayQuota)
                            root.cancelRateLimitRetry();

                        if (xhr.status === 429 && !perDayQuota && root.rateLimitRetries < root.maxRateLimitRetries) {
                            if ((xhr.responseText || "").indexOf("free_tier") !== -1)
                                root.onFreeTier = true;
                            const waitMs = root.rateLimitDelayMs(xhr);
                            root.rateLimitRetries++;
                            root.rateLimitSecondsLeft = Math.max(1, Math.round(waitMs / 1000));
                            root.currentActionText = qsTr("Rate limited - retrying in %1s…").arg(root.rateLimitSecondsLeft);
                            root.isTyping = true;
                            root.isThinking = true;
                            rateLimitRetryTimer.forChat = root.currentChatId;
                            rateLimitRetryTimer.forModel = root.activeModel();
                            rateLimitRetryTimer.retryFn = () => root.sendPrompt(promptText, isSystemToolResult, base64Image, toolName, true);
                            rateLimitRetryTimer.restart();
                            return;
                        }

                        var hint = "";
                        if (xhr.status === 429 && perDayQuota)
                            hint = " This model's daily free quota is used up - it resets tomorrow. Pick another model, or use Claude Code, which is not on this quota.";
                        else if (xhr.status === 429)
                            hint = " Rate limit reached and still limited after " + root.maxRateLimitRetries + " retries - wait a minute and try again.";
                        else if (root.isLocal && (xhr.status === 400 || xhr.status === 404 || xhr.status === 422))
                            // A local server has no key to be wrong about; 404 here
                            // nearly always means the saved model is not the one this
                            // server currently has loaded, which is normal when a
                            // llama-server has been switched to a different model.
                            hint = " The server rejected model \"" + model + "\" - pick one from the model list.";
                        else if (root.needsApiKey && (xhr.status === 401 || xhr.status === 403))
                            hint = " Check your API key.";
                        var errMsg = (xhr.status === 0) ? "Generation canceled" : (providerName + " request failed (status " + xhr.status + ")." + hint + apiDetail);
                        var currentText = chatHistory.get(chatHistory.count - 1).text;
                        if (currentText.trim() === "") {
                            chatHistory.setProperty(chatHistory.count - 1, "text", errMsg);
                        } else {
                            chatHistory.setProperty(chatHistory.count - 1, "text", currentText + "\n\n*[" + errMsg + "]*");
                        }
                        chatHistory.setProperty(chatHistory.count - 1, "isFinished", true);
                        isTyping = false;
                        isThinking = false;
                        inAgentLoop = false;
                        saveHistory();
                    }
                }
            }
        };

        var enableTools = GlobalConfig.ai.enableCelestialMode;
        var sysPrompt = "You are a helpful AI assistant integrated into the user's desktop OS shell (Caelestia, running on KDE Plasma/Wayland).";
        if (enableTools) {
            sysPrompt += "\n\nYou have access to the following tools. To call a tool, output a <tool_call> block containing ONLY valid JSON. Do not output any text inside the block other than the JSON object.\n\nFORMAT:\n<tool_call>\n{\"name\": \"TOOL_NAME\", \"args\": {ARGUMENTS}}\n</tool_call>\n\nAVAILABLE TOOLS:\n- take_screenshot: Captures the user's screen for visual analysis. Args: none.\n  Example: <tool_call>\n{\"name\": \"take_screenshot\", \"args\": {}}\n</tool_call>\n\n- web_search: Searches the web. Args: query (string, required), page (number, optional).\n  Example: <tool_call>\n{\"name\": \"web_search\", \"args\": {\"query\": \"latest news\"}}\n</tool_call>\n\n- read_webpage: Fetches and reads the text of a URL. Args: url (string, required).\n  Example: <tool_call>\n{\"name\": \"read_webpage\", \"args\": {\"url\": \"https://example.com\"}}\n</tool_call>\n\n- open_app: Launches an installed desktop application. Args: app_name (string, required).\n  Example: <tool_call>\n{\"name\": \"open_app\", \"args\": {\"app_name\": \"dolphin\"}}\n</tool_call>\n\n- set_timer: Sets a countdown timer that fires a desktop notification. Args: seconds (number, required), message (string, required).\n  Example: <tool_call>\n{\"name\": \"set_timer\", \"args\": {\"seconds\": 300, \"message\": \"Break time!\"}}\n</tool_call>\n\n- get_weather: Gets the current local weather from the system dashboard. Args: none.\n  Example: <tool_call>\n{\"name\": \"get_weather\", \"args\": {}}\n</tool_call>\n\n- caelestia_command: Runs a caelestia CLI command. Valid subcommands: shell, toggle, scheme, search, screenshot, record, clipboard, emoji, wallpaper, resizer, install, update. Args: subcommand (string, required), args (string, optional extra flags).\n  Example: <tool_call>\n{\"name\": \"caelestia_command\", \"args\": {\"subcommand\": \"wallpaper\", \"args\": \"--random\"}}\n</tool_call>\n\nCRITICAL RULES:\n1. ALWAYS use a <tool_call> block to call a tool. NEVER pretend to perform actions in plain text.\n2. You may output a brief acknowledgment before the <tool_call> block (e.g. 'Opening Dolphin for you!') but you MUST include the block.\n3. You can include multiple <tool_call> blocks in one response.\n4. After receiving tool results, respond naturally to the user based on what the tool returned.";
        }
        
        var requestBody;
        if (useAnthropic) {
            // Anthropic Messages API: system prompt is a top-level field; messages must
            // carry non-empty content and cannot include the streaming placeholder.
            var claudeMessages = [];
            for (var i = 0; i < chatHistory.count; i++) {
                var msg = chatHistory.get(i);
                if (!msg.isUser && !msg.isFinished && (msg.text || "") === "")
                    continue;
                if ((msg.text || "") === "")
                    continue;
                claudeMessages.push({
                    "role": msg.isUser ? "user" : "assistant",
                    "content": msg.text
                });
            }

            if (isSystemToolResult) {
                var claudeContent;
                if (base64Image) {
                    claudeContent = [
                        { "type": "text", "text": promptText },
                        { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": base64Image } }
                    ];
                } else {
                    claudeContent = promptText;
                }
                claudeMessages.push({ "role": "user", "content": claudeContent });
            }

            requestBody = {
                "model": model,
                "max_tokens": 4096,
                "system": sysPrompt,
                "messages": claudeMessages,
                "stream": true
            };
        } else {
            var messages = [];
            messages.push({
                "role": "system",
                "content": sysPrompt
            });

            for (var j = 0; j < chatHistory.count; j++) {
                var m = chatHistory.get(j);
                messages.push({
                    "role": m.isUser ? "user" : "assistant",
                    "content": m.text || ""
                });
            }

            if (isSystemToolResult) {
                var toolMsg = {
                    "role": "user",
                    "content": promptText
                };
                if (base64Image) {
                    if (root.isOpenaiCompat) {
                        // OpenAI carries images inline in the content array as data URLs;
                        // Ollama takes a separate base64 "images" field.
                        toolMsg["content"] = [
                            { "type": "text", "text": promptText },
                            { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64," + base64Image } }
                        ];
                    } else {
                        toolMsg["images"] = [base64Image];
                    }
                }
                messages.push(toolMsg);
            }

            // Native tool-calling API removed; using text-based <tool_call> parsing instead,
            // which is compatible with all models including llama3, mistral, phi, etc.
            requestBody = {
                "model": model,
                "messages": messages,
                "stream": true
            };
        }

        xhr.send(JSON.stringify(requestBody));
    }

    Item {
        id: mainWrapper

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium

         // Mode Switcher Row (Chat / History)
         RowLayout {
             id: modeSwitcherRow

             anchors.top: parent.top
             anchors.left: parent.left
             anchors.right: parent.right
             anchors.rightMargin: 0
             z: 10
             spacing: Tokens.spacing.small

             StyledRect {
                 id: modeSwitcherBg

                 implicitWidth: modeRow.width
                 implicitHeight: 32
                 radius: Tokens.rounding.full
                 color: Colours.tPalette.m3surfaceContainer

                 StyledClippingRect {
                     z: -1
                     anchors.fill: parent
                     radius: Tokens.rounding.full

                     ShaderEffectSource {
                         id: switcherBlurSource

                         sourceItem: contentStack
                         sourceRect: {
                             var p = parent.mapToItem(contentStack, 0, 0);
                             return Qt.rect(p.x, p.y, parent.width, parent.height);
                         }
                     }
                     MultiEffect {
                         anchors.fill: parent
                         source: switcherBlurSource
                         blurEnabled: true
                         blurMax: 32
                     }
                 }

                 StyledRect {
                     width: isHistoryTab ? historyTab.width : chatTab.width
                     height: parent.height
                     radius: Tokens.rounding.full
                     color: Colours.palette.m3primary
                     x: isHistoryTab ? historyTab.x : chatTab.x
                     
                     Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                     Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                 }

                 Row {
                     id: modeRow

                     height: parent.height

                     Item {
                         id: chatTab

                         height: parent.height
                         width: !isHistoryTab ? 40 : chatContent.implicitWidth + Tokens.padding.medium * 2
                         

                         Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                         StateLayer {
                             radius: Tokens.rounding.full
                             onClicked: isHistoryTab = false
                         }

                         Row {
                             id: chatContent

                             anchors.centerIn: parent
                             spacing: Tokens.spacing.small

                             MaterialIcon {
                                 anchors.verticalCenter: parent.verticalCenter
                                 text: "chat"
                                 color: !isHistoryTab ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                             }
                             Text {
                                 anchors.verticalCenter: parent.verticalCenter
                                 text: "Chat"
                                 color: !isHistoryTab ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.body.small
                                 visible: isHistoryTab
                             }
                         }
                     }

                     Item {
                         id: historyTab

                         height: parent.height
                         width: isHistoryTab ? 40 : historyContent.implicitWidth + Tokens.padding.medium * 2
                         

                         Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                         StateLayer {
                             radius: Tokens.rounding.full
                             onClicked: isHistoryTab = true
                         }

                         Row {
                             id: historyContent

                             anchors.centerIn: parent
                             spacing: Tokens.spacing.small

                             MaterialIcon {
                                 anchors.verticalCenter: parent.verticalCenter
                                 text: "history"
                                 color: isHistoryTab ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                             }
                             Text {
                                 anchors.verticalCenter: parent.verticalCenter
                                 text: "History"
                                 color: isHistoryTab ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.body.small
                                 visible: !isHistoryTab
                             }
                         }
                     }
                 }
             }

         }

         // Provider + model (+ account) selectors on their own row; a Flow so the
         // pills wrap to a second line instead of overflowing a narrow sidebar.
         Flow {
             id: selectorRow

             anchors.top: modeSwitcherRow.bottom
             anchors.left: parent.left
             anchors.right: parent.right
             anchors.topMargin: Tokens.spacing.small
             z: 10
             spacing: Tokens.spacing.small

             // Provider Selector Split Button (Ollama / Claude Code)
             SplitButton {
                 id: providerSelector

                 type: SplitButton.Tonal
                 verticalPadding: 4
                 visible: root.providerList.length > 1
                 Layout.preferredWidth: implicitWidth

                 active: menuItems.find(m => m.modelData === root.provider) ?? menuItems[0] ?? null
                 menu.onItemSelected: item => {
                     GlobalConfig.ai.defaultProvider = item.modelData;
                 }

                 menuItems: providerVariants.instances

                 fallbackIcon: "cloud"
                 fallbackText: qsTr("Provider")
                 stateLayer.disabled: true

                 Variants {
                     id: providerVariants

                     model: root.providerList

                     delegate: MenuItem {
                         required property string modelData

                         text: root.providerLabel(modelData)
                     }
                 }
             }

             // Model Selector Split Button
             SplitButton {
                 id: modelSelector

                 type: SplitButton.Tonal
                 verticalPadding: 4
                 Layout.preferredWidth: implicitWidth

                 active: menuItems.find(m => m.modelData === root.activeModel()) ?? menuItems[0] ?? null
                 menu.onItemSelected: item => {
                     if (root.isClaudeCode) {
                         GlobalConfig.ai.defaultClaudeCodeModel = item.modelData;
                         // Effort levels differ per model — reset to default on model change.
                         GlobalConfig.ai.claudeCodeEffort = "default";
                     } else if (root.isClaude)
                         GlobalConfig.ai.defaultClaudeModel = item.modelData;
                     else if (root.isOpenaiCompat)
                         GlobalConfig.ai[root.defaultModelField(root.provider)] = item.modelData;
                     else
                         GlobalConfig.ai.defaultOllamaModel = item.modelData;
                 }

                 menuItems: modelVariants.instances

                 fallbackIcon: "smart_toy"
                 fallbackText: qsTr("Select Model")
                 stateLayer.disabled: true

                 Variants {
                     id: modelVariants

                     model: {
                         if (root.isClaudeCode)
                             return root.claudeCodeModelsList;
                         if (root.isClaude)
                             return root.claudeModelsList;
                         if (root.isOpenaiCompat)
                             return root.openaiCompatModelList();
                         return root.ollamaModelsList;
                     }

                     delegate: MenuItem {
                         required property string modelData

                         text: modelData
                     }
                 }
             }

             // Effort / thinking-level Selector (Claude Code).
             SplitButton {
                 id: effortSelector

                 type: SplitButton.Tonal
                 verticalPadding: 4
                 visible: root.isClaudeCode && root.claudeCodeEffortOptions.length > 0

                 active: menuItems.find(m => m.modelData === (GlobalConfig.ai.claudeCodeEffort || "default")) ?? menuItems[0] ?? null
                 menu.onItemSelected: item => {
                     GlobalConfig.ai.claudeCodeEffort = item.modelData;
                 }

                 menuItems: effortVariants.instances

                 fallbackIcon: "neurology"
                 fallbackText: qsTr("Effort")
                 stateLayer.disabled: true

                 Variants {
                     id: effortVariants

                     model: root.claudeCodeEffortOptions

                     delegate: MenuItem {
                         required property string modelData

                         text: modelData
                     }
                 }
             }

             // Account Selector (Claude Code multi-login) — only when >1 account exists.
             SplitButton {
                 id: accountSelector

                 type: SplitButton.Tonal
                 verticalPadding: 4
                 visible: root.isClaudeCode && root.claudeAccountIds.length > 1

                 active: menuItems.find(m => m.modelData === (GlobalConfig.ai.activeClaudeAccount || "")) ?? menuItems[0] ?? null
                 menu.onItemSelected: item => {
                     GlobalConfig.ai.activeClaudeAccount = item.modelData;
                 }

                 menuItems: accountVariants.instances

                 fallbackIcon: "person"
                 fallbackText: qsTr("Account")
                 stateLayer.disabled: true

                 Variants {
                     id: accountVariants

                     model: root.claudeAccountIds

                     delegate: MenuItem {
                         required property string modelData

                         text: root.accountLabel(modelData)
                     }
                 }
             }


         }
         
         Item {
             id: contentStack

             anchors.top: selectorRow.bottom
             anchors.bottom: parent.bottom
             anchors.left: parent.left
             anchors.right: parent.right
             anchors.topMargin: Tokens.spacing.medium

             // Chat View
             Item {
                 anchors.fill: parent
                 opacity: !isHistoryTab ? 1 : 0
                 visible: opacity > 0

                 Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                 VerticalFadeListView {
                     id: listView

                     anchors.top: parent.top
                     anchors.bottom: inputBoxRow.top
                     anchors.left: parent.left
                     anchors.right: parent.right
                     anchors.bottomMargin: Tokens.spacing.medium
                     spacing: Tokens.spacing.medium
                     model: chatHistory
                     boundsBehavior: Flickable.StopAtBounds
                     
                     ColumnLayout {
                         anchors.centerIn: parent
                         opacity: chatHistory.count === 0 && !isTyping && !isThinking ? 1.0 : 0.0
                         visible: opacity > 0

                         Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                         spacing: Tokens.spacing.large

                         Item {
                             Layout.alignment: Qt.AlignHCenter
                             implicitWidth: 72
                             implicitHeight: 72

                             Logo {
                                 id: emptyStateLogo

                                 anchors.fill: parent
                                 visible: false // hide original for MultiEffect to take over
                             }

                             MultiEffect {
                                 anchors.fill: parent
                                 source: emptyStateLogo
                                 colorization: 1.0
                                 colorizationColor: Colours.palette.m3primary
                             }
                         }

                         StyledText {
                             id: greetingText
                             Layout.alignment: Qt.AlignHCenter
                             Layout.maximumWidth: listView.width - (Tokens.padding.large * 2)

                             horizontalAlignment: Text.AlignHCenter
                             wrapMode: Text.Wrap
                             font: Tokens.font.title.medium
                             color: Colours.palette.m3onSurfaceVariant

                             property var phrases: [
                                 "Ask away, %1!",
                                 "How can I help you today, %1?",
                                 "What's on your mind, %1?",
                                 "Ready when you are, %1!",
                                 "Let's get started, %1.",
                                 "What shall we explore today, %1?",
                                 "I'm all ears, %1!"
                             ]

                             Component.onCompleted: {
                                 var user = Quickshell.env("USER") || "user";
                                 var userCapitalized = user.charAt(0).toUpperCase() + user.slice(1);
                                 var phrase = phrases[Math.floor(Math.random() * phrases.length)];
                                 text = phrase.replace("%1", userCapitalized);
                             }
                         }
                     }

                     ScrollBar.vertical: StyledScrollBar {
                         flickable: listView
                     }

                     footer: Item {
                         width: listView.width
                         height: isThinking ? bubbleBg.height + Tokens.spacing.medium : 0
                         visible: opacity > 0
                         opacity: isThinking ? 1 : 0
                         
                         Behavior on height { Anim { type: Anim.DefaultSpatial } }
                         Behavior on opacity { Anim { type: Anim.DefaultSpatial } }

                         StyledRect {
                             id: bubbleBg

                             y: Tokens.spacing.medium / 2
                             width: Math.min(listView.width * 0.85, footerCol.implicitWidth + Tokens.padding.medium * 2 + 8)
                             height: footerCol.implicitHeight + Tokens.padding.medium * 2
                             radius: Tokens.rounding.large
                             color: Colours.tPalette.m3surfaceContainer

                             // Asymmetric corners
                             topLeftRadius: Tokens.rounding.large
                             topRightRadius: Tokens.rounding.large
                             bottomLeftRadius: 4
                             bottomRightRadius: Tokens.rounding.large

                             Column {
                                 id: footerCol

                                 anchors.fill: parent
                                 anchors.margins: Tokens.padding.medium
                                 spacing: Tokens.spacing.small
                                 
                                 Row {
                                     spacing: Tokens.spacing.small
                                     
                                     LoadingIndicator {
                                         width: 20
                                         height: 20
                                         color: Colours.palette.m3primary
                                     }
                                     
                                     // M3 Expressive Animated Text Wrapper
                                     Item {
                                         width: mainText.implicitWidth
                                         height: mainText.implicitHeight
                                         // The bubble smoothly expands/shrinks as the text width changes

                                         Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                         
                                         StyledText {
                                             id: mainText

                                             text: displayedText
                                             color: Colours.palette.m3onSurfaceVariant
                                             font: Tokens.font.body.small
                                             
                                             property string displayedText: root.currentActionText

                                             property string nextText: ""

                                             transform: Translate { id: textTrans; y: 0 }
                                             opacity: 1.0

                                             Connections {
                                                 target: root

                                                 function onCurrentActionTextChanged() {
                                                     if (root.currentActionText !== mainText.displayedText) {
                                                         mainText.nextText = root.currentActionText;
                                                         switchAnim.restart();
                                                     }
                                                 }
                                             }

                                             SequentialAnimation {
                                                 id: switchAnim

                                                 ParallelAnimation {
                                                     NumberAnimation { target: textTrans; property: "y"; to: -8; duration: 150; easing.type: Easing.InCubic }
                                                     NumberAnimation { target: mainText; property: "opacity"; to: 0.0; duration: 150; easing.type: Easing.InCubic }
                                                 }
                                                 PropertyAction { target: mainText; property: "displayedText"; value: mainText.nextText }
                                                 PropertyAction { target: textTrans; property: "y"; value: 8 }
                                                 ParallelAnimation {
                                                     NumberAnimation { target: textTrans; property: "y"; to: 0; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                                                     NumberAnimation { target: mainText; property: "opacity"; to: 1.0; duration: 250; easing.type: Easing.OutQuad }
                                                 }
                                             }

                                             SequentialAnimation {
                                                 running: isThinking && !switchAnim.running
                                                 loops: Animation.Infinite

                                                 NumberAnimation { target: mainText; property: "opacity"; from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                                                 NumberAnimation { target: mainText; property: "opacity"; from: 0.4; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                                             }
                                         }
                                     }
                                     
                                     Item {
                                         visible: root.currentThoughtText !== ""
                                         width: Tokens.spacing.medium
                                         height: 1
                                     }
                                     
                                     Item {
                                         visible: root.currentThoughtText !== ""
                                         width: thoughtRowFooter.implicitWidth
                                         height: thoughtRowFooter.implicitHeight

                                         Row {
                                             id: thoughtRowFooter

                                             spacing: Tokens.spacing.small

                                             MaterialIcon {
                                                 text: "expand_more"
                                                 color: Colours.palette.m3onSurfaceVariant
                                                 font: Tokens.font.icon.small
                                                 rotation: root.isThoughtExpanded ? 180 : 0

                                                 Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                             }
                                         }
                                         MouseArea {
                                             anchors.fill: parent
                                             anchors.margins: -10
                                             cursorShape: Qt.PointingHandCursor
                                             onClicked: root.isThoughtExpanded = !root.isThoughtExpanded
                                         }
                                     }
                                 }
                                 Item {
                                     id: footerThoughtContentWrapper

                                     width: footerThoughtContent.width
                                     height: root.isThoughtExpanded ? footerThoughtContent.implicitHeight : 0
                                     clip: true
                                     
                                     Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                                     TextEdit {
                                         id: footerThoughtContent

                                         width: Math.min(implicitWidth, listView.width * 0.85 - Tokens.padding.medium * 2)
                                         textFormat: Text.MarkdownText
                                         text: root.currentThoughtText
                                         color: Colours.palette.m3onSurfaceVariant
                                         font: Tokens.font.body.small
                                         wrapMode: Text.Wrap
                                         readOnly: true
                                         selectByMouse: true
                                         selectionColor: Colours.palette.m3primary
                                         selectedTextColor: Colours.palette.m3onPrimary
                                         opacity: root.isThoughtExpanded ? 1.0 : 0.0
                                         
                                         Behavior on opacity {
                                             SequentialAnimation {
                                                 PauseAnimation { duration: root.isThoughtExpanded ? 100 : 0 }
                                                 NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                                             }
                                         }
                                     }
                                 }
                             }
                         }
                     }

                     delegate: Item {
                         id: delegateItem

                         required property string text
                         required property bool isUser
                         required property bool isFinished
                         required property string thoughtText

                         width: listView.width - Tokens.padding.large
                         visible: (!delegateItem.isFinished && isThinking) ? false : (delegateItem.text !== "" || delegateItem.thoughtText !== "")
                         height: visible ? bubbleRect.height : 0
                         
                         scale: 0.0
                         opacity: 0.0
                         
                         Component.onCompleted: {
                             popInAnim.start();
                         }
                         
                         ParallelAnimation {
                             id: popInAnim

                             NumberAnimation { target: delegateItem; property: "scale"; from: 0.8; to: 1.0; duration: 300; easing.type: Easing.OutBack }
                             NumberAnimation { target: delegateItem; property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutQuad }
                         }
                         
                         SequentialAnimation {
                             id: popDoneAnim

                             NumberAnimation { target: delegateItem; property: "scale"; from: 1.0; to: 1.02; duration: 100; easing.type: Easing.OutQuad }
                             NumberAnimation { target: delegateItem; property: "scale"; from: 1.02; to: 1.0; duration: 150; easing.type: Easing.OutSine }
                         }
                         
                         onIsFinishedChanged: {
                             if (isFinished) popDoneAnim.start();
                         }

                         StyledRect {
                             id: bubbleRect

                             readonly property real maxBubbleWidth: delegateItem.width * 0.85

                             anchors.right: delegateItem.isUser ? parent.right : undefined
                             anchors.left: delegateItem.isUser ? undefined : parent.left
                             
                             // Let implicitWidth dictate width (with +8 buffer for layout engine) to stop short words from splitting line breaks
                             width: Math.min(maxBubbleWidth, bubbleLayout.implicitWidth + Tokens.padding.medium * 2 + 8)
                             height: bubbleLayout.implicitHeight + Tokens.padding.medium * 2
                             radius: Tokens.rounding.large
                             color: delegateItem.isUser ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                             // Asymmetric corners
                             topLeftRadius: Tokens.rounding.large
                             topRightRadius: Tokens.rounding.large
                             bottomLeftRadius: delegateItem.isUser ? Tokens.rounding.large : 4
                             bottomRightRadius: delegateItem.isUser ? 4 : Tokens.rounding.large
                             
                             Column {
                                 id: bubbleLayout

                                 anchors.top: parent.top
                                 anchors.left: parent.left
                                 anchors.margins: Tokens.padding.medium
                                 spacing: Tokens.spacing.small

                                 property string delegateThought: delegateItem.thoughtText

                                 property bool isExpanded: false

                                 Item {
                                     visible: bubbleLayout.delegateThought !== ""
                                     implicitWidth: thoughtRow.implicitWidth
                                     implicitHeight: thoughtRow.implicitHeight
                                     height: visible ? implicitHeight : 0

                                     Row {
                                         id: thoughtRow

                                         spacing: Tokens.spacing.small

                                         Text {
                                             text: qsTr("Thought Process")
                                             color: Colours.palette.m3onSurfaceVariant
                                             font: Tokens.font.body.small
                                         }
                                         MaterialIcon {
                                             id: thoughtArrow

                                             text: "expand_more"
                                             color: Colours.palette.m3onSurfaceVariant
                                             font: Tokens.font.icon.small
                                             rotation: bubbleLayout.isExpanded ? 180 : 0

                                             Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                         }
                                     }
                                     MouseArea {
                                         anchors.fill: parent
                                         cursorShape: Qt.PointingHandCursor
                                         onClicked: bubbleLayout.isExpanded = !bubbleLayout.isExpanded
                                     }
                                 }

                                 Item {
                                     id: thoughtContentWrapper

                                     width: thoughtContent.width
                                     height: bubbleLayout.isExpanded ? thoughtContent.implicitHeight : 0
                                     clip: true
                                     
                                     Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                                     TextEdit {
                                         id: thoughtContent

                                         width: Math.min(implicitWidth, bubbleRect.maxBubbleWidth - Tokens.padding.medium * 2)
                                         textFormat: Text.MarkdownText
                                         
                                         property string fullThought: bubbleLayout.delegateThought
                                         
                                         property bool cursorVisible: true

                                         Timer {
                                             running: !delegateItem.isFinished
                                             repeat: true
                                             interval: 400
                                             onTriggered: thoughtContent.cursorVisible = !thoughtContent.cursorVisible
                                         }
                                         
                                         text: delegateItem.isFinished ? fullThought : fullThought + (cursorVisible ? "▌" : "")
                                         
                                         color: Colours.palette.m3onSurfaceVariant

                                         font: Tokens.font.body.small

                                         wrapMode: Text.Wrap

                                         readOnly: true

                                         selectByMouse: true

                                         selectionColor: Colours.palette.m3primary

                                         selectedTextColor: Colours.palette.m3onPrimary

                                         opacity: bubbleLayout.isExpanded ? 1.0 : 0.0
                                         
                                         Behavior on opacity {
                                             SequentialAnimation {
                                                 PauseAnimation { duration: bubbleLayout.isExpanded ? 100 : 0 }
                                                 NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                                             }
                                         }
                                     }
                                 }

                                 TextEdit {
                                     id: messageText

                                     textFormat: Text.MarkdownText
                                     width: Math.min(implicitWidth, bubbleRect.maxBubbleWidth - Tokens.padding.medium * 2)
                                     
                                     property string fullText: delegateItem.text !== undefined ? delegateItem.text : ""
                                     
                                     property bool cursorVisible: true

                                     Timer {
                                         running: !delegateItem.isFinished
                                         repeat: true
                                         interval: 400
                                         onTriggered: messageText.cursorVisible = !messageText.cursorVisible
                                     }
                                     
                                     text: delegateItem.isFinished ? fullText : fullText + (cursorVisible ? "▌" : "")
                                     
                                     color: delegateItem.isUser ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface

                                     font: Tokens.font.body.small

                                     wrapMode: Text.Wrap

                                     readOnly: true

                                     selectByMouse: true

                                     selectionColor: Colours.palette.m3primary

                                     selectedTextColor: Colours.palette.m3onPrimary

                                     MouseArea {
                                         anchors.fill: parent
                                         hoverEnabled: true
                                         cursorShape: Qt.IBeamCursor
                                         propagateComposedEvents: true
                                         onPressed: mouse => mouse.accepted = false
                                     }
                                 }
                             }
                         }
                     }
                 }

                 // Scroll to bottom button
                 Item {
                     id: scrollBtnWrapper

                     anchors.bottom: inputBoxRow.top
                     anchors.bottomMargin: Tokens.spacing.large
                     anchors.right: parent.right
                     anchors.rightMargin: Tokens.padding.large
                     width: 36
                     height: 36
                     z: 20
                     opacity: (!listView.atYEnd && chatHistory.count > 0) ? 1.0 : 0.0
                     visible: opacity > 0

                     Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                     StyledRect {
                         id: scrollBtnBg

                         anchors.fill: parent
                         radius: 18
                         color: Colours.tPalette.m3surfaceContainerHigh
                     }

                     MultiEffect {
                         anchors.fill: scrollBtnBg
                         source: scrollBtnBg
                         shadowEnabled: true
                         shadowOpacity: 0.3
                         shadowBlur: 0.5
                         shadowVerticalOffset: 2
                     }

                     MaterialIcon {
                         anchors.centerIn: parent
                         text: "arrow_downward"
                         font: Tokens.font.icon.small
                         color: Colours.palette.m3onSurface
                     }

                     MouseArea {
                         anchors.fill: parent
                         cursorShape: Qt.PointingHandCursor
                         onClicked: listView.positionViewAtEnd()
                     }
                 }

                 // Prompt suggestion chips (Claude Code) — float just above the input.
                 ColumnLayout {
                     id: suggestionBox

                     anchors.bottom: inputBoxRow.top
                     anchors.bottomMargin: Tokens.spacing.small
                     anchors.left: parent.left
                     anchors.right: parent.right
                     z: 11
                     spacing: Tokens.spacing.small
                     visible: root.isClaudeCode && root.promptSuggestions.length > 0

                     // Header with a close button.
                     RowLayout {
                         Layout.fillWidth: true
                         spacing: Tokens.spacing.small

                         StyledText {
                             Layout.fillWidth: true
                             text: qsTr("Suggestions")
                             color: Colours.palette.m3onSurfaceVariant
                             font: Tokens.font.label.small
                         }

                         Item {
                             Layout.preferredWidth: 24
                             Layout.preferredHeight: 24

                             MaterialIcon {
                                 anchors.centerIn: parent
                                 text: "close"
                                 color: closeSugMouse.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                             }

                             MouseArea {
                                 id: closeSugMouse

                                 anchors.fill: parent
                                 hoverEnabled: true
                                 cursorShape: Qt.PointingHandCursor
                                 onClicked: root.promptSuggestions = []
                             }
                         }
                     }

                     Repeater {
                         model: root.promptSuggestions

                         StyledRect {
                             required property string modelData
                             Layout.fillWidth: true

                             implicitHeight: sugChipText.implicitHeight + Tokens.padding.medium * 2
                             radius: Tokens.rounding.large
                             color: Colours.tPalette.m3surfaceContainerHigh

                             StateLayer {
                                 radius: Tokens.rounding.large
                                 onClicked: {
                                     inputArea.text = modelData;
                                     root.promptSuggestions = [];
                                     inputArea.forceActiveFocus();
                                 }
                             }

                             StyledText {
                                 id: sugChipText

                                 anchors.left: parent.left
                                 anchors.right: parent.right
                                 anchors.top: parent.top
                                 anchors.leftMargin: Tokens.padding.medium
                                 anchors.rightMargin: Tokens.padding.medium
                                 anchors.topMargin: Tokens.padding.medium
                                 text: parent.modelData
                                 color: Colours.palette.m3onSurface
                                 font: Tokens.font.body.small
                                 wrapMode: Text.Wrap
                             }
                         }
                     }
                 }

                 // Input Box Row
                 StyledRect {
                     id: inputBoxRow

                     anchors.bottom: parent.bottom
                     anchors.left: parent.left
                     anchors.right: parent.right
                     z: 10
                     implicitHeight: Math.max(48, inputArea.implicitHeight + Tokens.padding.medium * 2)
                     color: Colours.tPalette.m3surfaceContainer
                     radius: 24

                     StyledClippingRect {
                         z: -1
                         anchors.fill: parent
                         radius: 24

                         ShaderEffectSource {
                             id: inputBlurSource

                             sourceItem: contentStack
                             sourceRect: {
                                 var p = parent.mapToItem(contentStack, 0, 0);
                                 return Qt.rect(p.x, p.y, parent.width, parent.height);
                             }
                         }
                         MultiEffect {
                             anchors.fill: parent
                             source: inputBlurSource
                             blurEnabled: true
                             blurMax: 32
                         }
                     }

                     StateLayer {
                         id: inputStateLayer

                         anchors.fill: parent
                         radius: 24
                         hoverEnabled: false
                         cursorShape: Qt.IBeamCursor
                         onClicked: inputArea.forceActiveFocus()
                     }

                     RowLayout {
                         anchors.fill: parent
                         anchors.leftMargin: Tokens.padding.large
                         anchors.rightMargin: Tokens.padding.small
                         spacing: Tokens.spacing.small

                         ScrollView {
                             id: inputScroll
                             Layout.fillWidth: true
                             Layout.fillHeight: true
                             
                             TextArea {
                                 id: inputArea

                                 verticalAlignment: TextInput.AlignVCenter
                                 placeholderText: qsTr("Ask assistant...")
                                 color: Colours.palette.m3onSurface
                                 placeholderTextColor: Colours.palette.m3outline
                                 font: Tokens.font.body.small
                                 wrapMode: Text.Wrap
                                 selectByMouse: true
                                 background: null

                                 MouseArea {
                                     anchors.fill: parent
                                     hoverEnabled: true
                                     cursorShape: Qt.IBeamCursor
                                     propagateComposedEvents: true
                                     onPressed: mouse => {
                                          var mapped = mapToItem(inputStateLayer, mouse.x, mouse.y);
                                          inputStateLayer.press(mapped.x, mapped.y);
                                          mouse.accepted = false;
                                      }
                                 }

                                 Keys.onPressed: event => {
                                     if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                                         event.accepted = true;
                                         root.sendPrompt(inputArea.text);
                                         inputArea.clear();
                                     }
                                 }
                             }
                         }

                         // Prompt suggestions trigger (Claude Code).
                         Item {
                             visible: root.isClaudeCode
                             Layout.preferredWidth: visible ? 32 : 0
                             Layout.preferredHeight: 32

                             MaterialIcon {
                                 anchors.centerIn: parent
                                 text: root.loadingSuggestions ? "hourglass_empty" : "lightbulb"
                                 color: sugMouse.containsMouse ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                             }

                             MouseArea {
                                 id: sugMouse

                                 anchors.fill: parent
                                 hoverEnabled: true
                                 cursorShape: Qt.PointingHandCursor
                                 onClicked: root.fetchPromptSuggestions()
                             }
                         }

                         Item {
                             Layout.preferredWidth: 36
                             Layout.preferredHeight: 36

                             MaterialShape {
                                 anchors.fill: parent
                                 color: root.isTyping ? Colours.palette.m3error : (inputArea.text.length > 0 ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainerHigh, 2))
                                 shape: root.isTyping ? MaterialShape.Cookie4Sided : (inputArea.text.length > 0 ? MaterialShape.Arrow : MaterialShape.Circle)
                                 scale: (inputArea.text.length === 0 && !root.isTyping) ? 1 : sendMouse.pressed ? 0.6 : sendMouse.containsMouse ? 0.8 : 0.7
                                 rotation: 0
                                 
                                 Behavior on scale { Anim { type: Anim.FastSpatial } }
                                 Behavior on color { CAnim {} }

                                 MouseArea {
                                     id: sendMouse

                                     anchors.fill: parent
                                     hoverEnabled: true
                                     cursorShape: (inputArea.text.length > 0 || root.isTyping) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                     onClicked: {
                                         if (root.isTyping) {
                                             root.cancelRateLimitRetry();
                                             if (root.currentRequest) {
                                                 root.currentRequest.abort();
                                             }
                                             root.stopClaudeCode();
                                             root.isTyping = false;
                                             root.isThinking = false;
                                             root.inAgentLoop = false;
                                             typingTimer.stop();
                                             chatHistory.setProperty(chatHistory.count - 1, "isFinished", true);
                                             saveHistory();
                                         } else if (inputArea.text.length > 0) {
                                             root.sendPrompt(inputArea.text);
                                             inputArea.clear();
                                         }
                                     }
                                 }
                             }

                             MaterialIcon {
                                 anchors.centerIn: parent
                                 text: "arrow_upward"
                                 color: Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                                 opacity: (inputArea.text.length > 0 || root.isTyping) ? 0 : 1

                                 Behavior on opacity { Anim { type: Anim.DefaultEffects } }
                             }
                         }
                     }
                 }
             }

             // History Grid View
             Item {
                 anchors.fill: parent
                 opacity: isHistoryTab ? 1 : 0
                 visible: opacity > 0

                 Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                 GridView {
                     anchors.top: parent.top
                     anchors.left: parent.left
                     anchors.right: parent.right
                     anchors.bottom: newChatButton.top
                     anchors.bottomMargin: Tokens.spacing.medium
                     
                     cellWidth: width / 2
                     cellHeight: 90
                     model: historySessionsModel

                     delegate: Item {
                         required property var model
                         property string chatId: model && model.id ? String(model.id) : ""
                         property string chatTitle: model && model.title ? String(model.title) : ""

                         width: GridView.view.cellWidth
                         height: GridView.view.cellHeight

                         StyledRect {
                             anchors.fill: parent
                             anchors.margins: Tokens.spacing.small
                             radius: Tokens.rounding.medium
                             color: Colours.tPalette.m3surfaceContainerHigh

                             StateLayer {
                                 radius: Tokens.rounding.medium
                                 onClicked: loadChat(chatId)
                             }

                             RowLayout {
                                 anchors.fill: parent
                                 anchors.margins: Tokens.padding.small
                                 spacing: Tokens.spacing.medium

                                 StyledRect {
                                     Layout.preferredWidth: 32
                                     Layout.preferredHeight: 32
                                     radius: 16
                                     color: Colours.tPalette.m3surfaceContainerHighest

                                     MaterialIcon {
                                         anchors.centerIn: parent
                                         text: "chat"
                                         color: Colours.palette.m3onSurfaceVariant
                                         font: Tokens.font.icon.small
                                     }
                                 }

                                 ColumnLayout {
                                     Layout.fillWidth: true
                                     spacing: 0

                                     Text {
                                         Layout.fillWidth: true
                                         Layout.alignment: Qt.AlignVCenter
                                         text: chatTitle ? chatTitle : "New Chat"
                                         color: Colours.palette.m3onSurface
                                         font: Tokens.font.label.small
                                         elide: Text.ElideRight
                                          wrapMode: Text.Wrap
                                          maximumLineCount: 3
                                     }
                                 }

                                 Item {
                                     Layout.alignment: Qt.AlignTop | Qt.AlignRight
                                     Layout.preferredWidth: 24
                                     Layout.preferredHeight: 24
                                     
                                     StyledRect {
                                         anchors.fill: parent
                                         radius: 12
                                         color: Colours.palette.m3onSurfaceVariant
                                         opacity: deleteMouseArea.containsMouse ? 0.12 : 0.0

                                         Behavior on opacity { NumberAnimation { duration: 150 } }
                                     }

                                     MaterialIcon {
                                         anchors.centerIn: parent
                                         text: "close"
                                         font: Tokens.font.icon.small
                                         color: Colours.palette.m3onSurfaceVariant
                                     }

                                     MouseArea {
                                         id: deleteMouseArea

                                         anchors.fill: parent
                                         hoverEnabled: true
                                         cursorShape: Qt.PointingHandCursor
                                         onClicked: deleteChat(chatId)
                                     }
                                 }
                             }
                         }
                     }
                 }

                 // "Clear All" button
                 StyledRect {
                     id: clearAllButton

                     anchors.bottom: parent.bottom
                     anchors.left: parent.left
                     width: clearAllLayout.implicitWidth + Tokens.padding.large * 2
                     height: 32
                     radius: 16
                     color: Colours.palette.m3errorContainer

                     StateLayer {
                         radius: 16
                         onClicked: clearAllHistory()
                     }

                     RowLayout {
                         id: clearAllLayout

                         anchors.centerIn: parent
                         spacing: Tokens.spacing.small

                         MaterialIcon {
                             text: "delete"
                             color: Colours.palette.m3onErrorContainer
                             font: Tokens.font.icon.small
                         }
                         Text {
                             text: qsTr("Clear All")
                             color: Colours.palette.m3onErrorContainer
                             font: Tokens.font.body.small
                         }
                     }
                 }

                 // "New Chat" button
                 StyledRect {
                     id: newChatButton

                     anchors.bottom: parent.bottom
                     anchors.right: parent.right
                     width: newChatLayout.implicitWidth + Tokens.padding.large * 2
                     height: 32
                     radius: 16
                     color: Colours.palette.m3primaryContainer

                     StateLayer {
                         radius: 16
                         onClicked: createNewChat()
                     }

                     RowLayout {
                         id: newChatLayout

                         anchors.centerIn: parent
                         spacing: Tokens.spacing.small

                         MaterialIcon {
                             text: "add"
                             color: Colours.palette.m3onPrimaryContainer
                             font: Tokens.font.icon.small
                         }
                         Text {
                             text: qsTr("New Chat")
                             color: Colours.palette.m3onPrimaryContainer
                             font: Tokens.font.body.small
                         }
                     }
                 }
             }
         }
    }
}