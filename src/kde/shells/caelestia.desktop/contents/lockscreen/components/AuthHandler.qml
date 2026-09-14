
import QtQuick
import org.kde.kscreenlocker as ScreenLocker

Item {
    id: root

    property var authenticatorTarget: {
        try {
            return authenticator;
        } catch (e) {
            return null;
        }
    }
    readonly property var activeAuthenticator: authenticatorTarget

    property bool isAuthenticating: false
    property bool localGraceLocked: false
    readonly property bool graceLocked: localGraceLocked || Boolean(activeAuthenticator && activeAuthenticator.graceLocked)
    property string authMessage: ""
    property string pendingPassword: ""

    property int lockoutSecondsRemaining: 0
    readonly property int lockoutMinutesRemaining: Math.ceil(lockoutSecondsRemaining / 60)
    readonly property bool lockoutActive: lockoutSecondsRemaining > 0
    readonly property string lockoutText: lockoutMinutesRemaining > 0 ? (lockoutMinutesRemaining + " min left") : ""

    property int fprintTries: 0
    property int maxFprintTries: 3
    property int timeoutInterval: 15000
    property int notificationDismissInterval: 5000
    property int graceLockInterval: 3000

    signal messageChanged(string message)
    signal shakeRequested()
    signal focusSecretRequested()
    signal clearPasswordRequested()
    signal notificationRepeated()
    signal succeeded()

    function isExactFailMsg(msg) {
        if (!msg) return false;
        var trimmed = (typeof msg === "string") ? msg.trim() : "";
        var lower = trimmed.toLowerCase();
        var localized = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed").trim();
        return lower === "unlocking failed" ||
               lower === "unlocking failed." ||
               trimmed === localized ||
               trimmed === (localized + ".");
    }

    function extractTimeInSeconds(text) {
        if (!text || typeof text !== "string") return -1;
        var hrMatch = text.match(/\b(\d+)\s*(?:hours?|hrs?|hr)\b/i);
        var minMatch = text.match(/\b(\d+)\s*(?:minutes?|mins?|min)\b/i);
        var secMatch = text.match(/\b(\d+)\s*(?:seconds?|secs?|sec)\b/i);

        var totalSec = 0;
        var found = false;

        if (hrMatch) { totalSec += parseInt(hrMatch[1], 10) * 3600; found = true; }
        if (minMatch) { totalSec += parseInt(minMatch[1], 10) * 60; found = true; }
        if (secMatch) { totalSec += parseInt(secMatch[1], 10); found = true; }

        return found ? totalSec : -1;
    }

    function stripTimeLines(text) {
        if (!text || typeof text !== "string") return "";
        var lines = text.split("\n");
        var kept = [];
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line) continue;
            if (extractTimeInSeconds(line) > 0) {
                continue;
            }
            if (isExactFailMsg(line)) {
                continue;
            }
            kept.push(line);
        }
        return kept.join("\n");
    }

    function handleMessage(msg) {
        if (!msg || (typeof msg === "string" && msg.trim().length === 0)) return;

        var extractedSec = extractTimeInSeconds(msg);
        if (extractedSec > 0) {
            root.lockoutSecondsRemaining = extractedSec;
            lockoutCountdownTimer.restart();
        }

        var filteredMsg = stripTimeLines(msg);
        if (!filteredMsg || filteredMsg.trim().length === 0 || isExactFailMsg(filteredMsg)) return;

        if (typeof parent !== "undefined" && typeof parent.notification !== "undefined") {
            if (!parent.notification) {
                parent.notification += filteredMsg;
            } else if (parent.notification.includes(filteredMsg)) {
                root.notificationRepeated();
            } else {
                parent.notification += "\n" + filteredMsg;
            }
            root.authMessage = parent.notification;
        } else {
            if (!root.authMessage) {
                root.authMessage = filteredMsg;
            } else if (!root.authMessage.includes(filteredMsg)) {
                root.authMessage += "\n" + filteredMsg;
            } else {
                root.notificationRepeated();
            }
        }

        notificationRemoveTimer.restart();
        root.messageChanged(root.authMessage);
    }

    function ensureAuthenticating() {
        if (root.graceLocked || root.isAuthenticating || (activeAuthenticator && activeAuthenticator.busy)) return;
        if (activeAuthenticator && typeof activeAuthenticator.startAuthenticating === "function") {
            activeAuthenticator.startAuthenticating();
        }
    }

    function startLogin(pass) {
        if (!pass || pass.length === 0 || root.isAuthenticating || root.graceLocked) return;
        root.clearAuthMessage();
        root.isAuthenticating = true;
        root.localGraceLocked = false;
        authTimeoutTimer.restart();

        if (activeAuthenticator) {
            var hasPrompt = Boolean(activeAuthenticator.promptForSecret || activeAuthenticator.prompt);
            if (typeof activeAuthenticator.respond === "function" && hasPrompt) {
                activeAuthenticator.respond(pass);
            } else {
                root.pendingPassword = pass;
                if (typeof activeAuthenticator.startAuthenticating === "function") {
                    activeAuthenticator.startAuthenticating();
                }
            }
        }
    }

    function clearAuthMessage() {
        root.authMessage = "";
        if (typeof parent !== "undefined" && typeof parent.notification !== "undefined") {
            parent.notification = "";
        }
        if (typeof root !== "undefined" && typeof root.notification !== "undefined") {
            root.notification = "";
        }
        notificationRemoveTimer.stop();
        root.messageChanged("");
    }

    Timer {
        id: authTimeoutTimer

        interval: root.timeoutInterval
        repeat: false
        onTriggered: {
            if (root.isAuthenticating || root.localGraceLocked) {
                root.isAuthenticating = false;
                root.localGraceLocked = false;
                root.pendingPassword = "";
                root.clearPasswordRequested();
                if (activeAuthenticator && typeof activeAuthenticator.cancel === "function") {
                    activeAuthenticator.cancel();
                }
                if (activeAuthenticator && typeof activeAuthenticator.startAuthenticating === "function") {
                    activeAuthenticator.startAuthenticating();
                }
                if (!root.authMessage) {
                    root.handleMessage(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Authentication timed out"));
                }
            }
        }
    }

    Timer {
        id: notificationRemoveTimer

        interval: root.notificationDismissInterval
        onTriggered: {
            root.clearAuthMessage();
        }
    }

    Timer {
        id: graceLockTimer

        interval: root.graceLockInterval
        repeat: false
        onTriggered: {
            root.clearPasswordRequested();
            if (activeAuthenticator && typeof activeAuthenticator.startAuthenticating === "function") {
                activeAuthenticator.startAuthenticating();
            }
            fallbackUnlockTimer.restart();
        }
    }

    Timer {
        id: fallbackUnlockTimer

        interval: 2000
        repeat: false
        onTriggered: {
            if (root.localGraceLocked || root.isAuthenticating) {
                root.localGraceLocked = false;
                root.isAuthenticating = false;
                root.focusSecretRequested();
            }
        }
    }

    Timer {
        id: lockoutCountdownTimer

        interval: 1000
        repeat: true
        running: root.lockoutSecondsRemaining > 0
        onTriggered: {
            if (root.lockoutSecondsRemaining > 0) {
                root.lockoutSecondsRemaining--;
            }
        }
    }

    Connections {
        function onFailed(kind, auth) {
            authTimeoutTimer.stop();
            root.pendingPassword = "";

            if (kind !== 0) {
                if (kind & ScreenLocker.Authenticator.Fingerprint) {
                    root.fprintTries++;
                    if (root.fprintTries >= root.maxFprintTries) {
                        root.handleMessage(i18ndc("plasma_shell_org.kde.plasma.desktop",
                            "@info:status", "Maximum fingerprint attempts reached. Please use password."));
                    }
                }
                return;
            }

            var authErr = (auth && auth.errorMessage) ? auth.errorMessage :
                          (activeAuthenticator && activeAuthenticator.errorMessage ? activeAuthenticator.errorMessage :
                          (activeAuthenticator && activeAuthenticator.infoMessage ? activeAuthenticator.infoMessage : ""));

            if (authErr) {
                root.handleMessage(authErr);
            }

            if (!graceLockTimer.running) {
                root.isAuthenticating = false;
                root.localGraceLocked = true;
                root.shakeRequested();
                graceLockTimer.interval = root.graceLockInterval;
                graceLockTimer.restart();
            }
        }

        function onNoninteractiveError(kind, auth) {
            if (kind & ScreenLocker.Authenticator.Fingerprint) {
                root.fprintTries++;
                if (root.fprintTries >= root.maxFprintTries) {
                    root.pendingPassword = "";
                    root.handleMessage(i18ndc("plasma_shell_org.kde.plasma.desktop",
                        "@info:status", "Maximum fingerprint attempts reached. Please use password."));
                } else if (auth && auth.errorMessage) {
                    root.handleMessage(auth.errorMessage);
                }
            }
        }

        function onSucceeded() {
            root.isAuthenticating = false;
            root.localGraceLocked = false;
            root.pendingPassword = "";
            root.lockoutSecondsRemaining = 0;
            authTimeoutTimer.stop();
            graceLockTimer.stop();
            fallbackUnlockTimer.stop();
            lockoutCountdownTimer.stop();
            root.fprintTries = 0;
            root.succeeded();
            Qt.quit();
        }

        function onInfoMessageChanged() {
            if (activeAuthenticator && activeAuthenticator.infoMessage) {
                root.handleMessage(activeAuthenticator.infoMessage);
            }
        }

        function onErrorMessageChanged() {
            if (activeAuthenticator && activeAuthenticator.errorMessage) {
                root.handleMessage(activeAuthenticator.errorMessage);
            }
        }

        function onPromptChanged(msg) {
            if (activeAuthenticator && activeAuthenticator.prompt) {
                root.handleMessage(activeAuthenticator.prompt);
            }
            if (root.pendingPassword) {
                var pass = root.pendingPassword;
                root.pendingPassword = "";
                root.isAuthenticating = true;
                authTimeoutTimer.restart();
                if (activeAuthenticator && typeof activeAuthenticator.respond === "function") {
                    activeAuthenticator.respond(pass);
                }
            }
        }

        function onPromptForSecretChanged(msg) {
            fallbackUnlockTimer.stop();
            root.localGraceLocked = false;
            authTimeoutTimer.stop();
            if (root.pendingPassword) {
                var pass = root.pendingPassword;
                root.pendingPassword = "";
                root.isAuthenticating = true;
                authTimeoutTimer.restart();
                if (activeAuthenticator && typeof activeAuthenticator.respond === "function") {
                    activeAuthenticator.respond(pass);
                }
                return;
            }
            root.isAuthenticating = false;
            root.focusSecretRequested();
        }

        function onLoginFailedDelayStarted(kind, auth, uSecDelay) {
            authTimeoutTimer.stop();
            if (kind !== 0) {
                return;
            }
            root.isAuthenticating = false;
            root.localGraceLocked = true;
            root.shakeRequested();

            var delayMs = (uSecDelay && uSecDelay > 0) ? (Math.round(uSecDelay / 1000) + 150) : root.graceLockInterval;
            graceLockTimer.interval = Math.max(delayMs, root.graceLockInterval);
            graceLockTimer.restart();

            var msg = (auth && auth.errorMessage) ? auth.errorMessage :
                      (activeAuthenticator && activeAuthenticator.errorMessage ? activeAuthenticator.errorMessage :
                      (activeAuthenticator && activeAuthenticator.infoMessage ? activeAuthenticator.infoMessage : ""));
            if (msg) {
                root.handleMessage(msg);
            }
        }

        function onBusyChanged() {
            if (activeAuthenticator && typeof activeAuthenticator.busy !== "undefined" && !activeAuthenticator.busy) {
                if (root.isAuthenticating && !root.graceLocked && !graceLockTimer.running) {
                    root.isAuthenticating = false;
                    authTimeoutTimer.stop();
                }
            }
        }

        function onGraceLockedChanged() {
            if (activeAuthenticator && !activeAuthenticator.graceLocked) {
                fallbackUnlockTimer.stop();
                root.localGraceLocked = false;
                root.isAuthenticating = false;
                authTimeoutTimer.stop();
                root.focusSecretRequested();
            }
        }

        target: activeAuthenticator
        ignoreUnknownSignals: true
    }
}
