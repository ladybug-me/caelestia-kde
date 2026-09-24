
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

import org.kde.plasma.private.sessions
import Caelestia.Services

import "components"

Item {
    id: lockScreenUi

    readonly property real lockHeight: Math.min(width, height)
    readonly property real lockLong: lockHeight * 0.7 * (16.0 / 9.0)
    readonly property real lockShort: lockHeight * 0.7
    readonly property real centerScale: Math.max(0.65, lockHeight / 1080)
    readonly property real centerWidth: 400 * centerScale
    readonly property real passwordPillWidth: 300 * centerScale
    readonly property bool isPortrait: height > width * 1.2
    property bool use12h: Qt.locale().timeFormat(Locale.ShortFormat).toLowerCase().indexOf("a") !== -1
    property bool isCaelestiaMode: false
    property bool recolourLogo: true
    property bool hideNotifs: false
    property bool enableFprint: true
    property int maxFprintTries: 3
    readonly property alias fprintTries: authHandler.fprintTries
    property int profilePicShape: 13
    property bool rotateProfilePic: false
    property var sessionIcons: ({})
    property bool showSleep: true
    property bool showHibernate: false
    property bool showSwitchUser: true
    property bool showLogout: true
    property bool showReboot: false
    property bool showShutdown: false
    property bool blurWallpaper: false

    readonly property bool hasFingerprint: enableFprint && (fprintTries < maxFprintTries) && Boolean(authenticator.authenticatorTypes & ScreenLocker.Authenticator.Fingerprint)
    readonly property bool fprintDisabledDueToTries: enableFprint && (fprintTries >= maxFprintTries) && Boolean(authenticator.authenticatorTypes & ScreenLocker.Authenticator.Fingerprint)
    readonly property real bgRadius: 42 * (lockHeight / 1080)
    readonly property real bgMargin: 16 * (lockHeight / 1080)
    readonly property real cardRadius: bgRadius - bgMargin

    readonly property color clCardBg: alterColour(clSurfaceContainer, 0.60, 1)
    readonly property color clCardBgHigh: alterColour(clSurfaceContainerHigh, 0.60, 1)

    property color clSurface: "#0a0f0f"
    property color clSurfaceFg: "#dce8e6"
    property color clSurfaceContainer: "#131b1a"
    property color clSurfaceContainerHigh: "#192120"
    property color clSurfaceContainerHighest: "#1d2827"
    property color clPrimary: "#9bd0cc"
    property color clSecondary: "#b0ccc9"
    property color clPrimaryFg: "#0d4845"
    property color clError: "#fa746f"
    property color clSurfaceVariantFg: "#a2adac"
    property color clPrimaryContainer: "#255b58"
    property color clSecondaryContainer: "#27403e"
    property color clTertiary: "#d5efff"
    property color clOnTertiary: "#2e5c72"
    property color clOutline: "#6d7876"

    property var clTerms: []

    // Bumped whenever the greeter detects a resume, so the wallpaper blur binding
    // below looks the host's wallpaper item up again: it can be absent or
    // mid-teardown around a suspend (issue #815).
    property int wallpaperResolveNonce: 0

    readonly property bool isAuthenticating: authHandler.isAuthenticating
    readonly property var activePasswordPill: isPortrait ? portraitPasswordPill : passwordPill
    property string authMessage: ""
    property bool ready: false

    readonly property string sysinfoScriptPath: {
        var url = Qt.resolvedUrl("scripts/sysinfo.py").toString();
        return url.startsWith("file://") ? url.slice(7) : url;
    }

    readonly property int liveCpu: Math.round((Cpu.percentage ?? 0) * 100)
    readonly property int liveTemp: Math.round(Cpu.temperature ?? 0)
    readonly property int liveRam: Math.round((Memory.percentage ?? 0) * 100)
    readonly property int liveDisk: Math.round((Storage.percentage ?? 0) * 100)
    readonly property string ipcBin: "PATH=\"${CAELESTIA_BIN_DIR:-$HOME/.local/bin}:$PATH\" caelestia-shell-ipc"
    property var liveMedia: ({})
    property var liveNotifs: []
    property double notifsClearedAt: 0
    property bool isClearingNotifs: false
    property var greetingInfo: getGreeting()

    function getLuminance(c) {
        if (!c || (c.r === 0 && c.g === 0 && c.b === 0)) return 0;
        return Math.sqrt(0.299 * (c.r * c.r) + 0.587 * (c.g * c.g) + 0.114 * (c.b * c.b));
    }

    function alterColour(c, a, layer) {
        if (!c) return Qt.rgba(0.15, 0.15, 0.15, a);
        var luminance = getLuminance(c);
        if (luminance === 0) return Qt.rgba(0.12, 0.12, 0.12, a);
        var offset = 0.3 * (1 - 0.7) * 1.5;
        var scale = (luminance + offset) / luminance;
        var r = Math.max(0, Math.min(1, c.r * scale));
        var g = Math.max(0, Math.min(1, c.g * scale));
        var b = Math.max(0, Math.min(1, c.b * scale));
        return Qt.rgba(r, g, b, a);
    }

    function getGreeting() {
        var hour = new Date().getHours();
        if (hour >= 5 && hour < 12) return { greeting: qsTr("Good morning"), icon: "sunny", iconColor: lockScreenUi.clPrimary };
        if (hour >= 12 && hour < 17) return { greeting: qsTr("Good afternoon"), icon: "light_mode", iconColor: lockScreenUi.clPrimary };
        if (hour >= 17 && hour < 22) return { greeting: qsTr("Good evening"), icon: "routine", iconColor: lockScreenUi.clSecondary };
        return { greeting: qsTr("Good night"), icon: "bedtime", iconColor: lockScreenUi.clPrimary };
    }

    function handleMessage(msg) { authHandler.handleMessage(msg); }

    function startLogin(pass) {
        msgExitAnim.stop();
        msgAppearAnim.stop();
        msgFlashAnim.stop();
        errorText.visible = false;
        portraitErrorText.visible = false;
        errorText.opacity = 0;
        portraitErrorText.opacity = 0;
        lockScreenUi.authMessage = "";
        authHandler.startLogin(pass);
    }

    function ensureAuthenticating() {
        authHandler.ensureAuthenticating();
    }

    // Re-runs the one-shot loaders below once the view is shown again: each disconnects
    // its source after its first answer, so a suspend in between leaves the greeter
    // running on the palette and config it read before the sleep (issue #815).
    function rearmAfterResume() {
        schemeLoader.connectSource("cat ~/.local/state/caelestia/scheme.json 2>/dev/null");
        configLoader.connectSource("cat ~/.config/caelestia/shell.json 2>/dev/null");
        fetchLoader.connectSource("python3 " + lockScreenUi.sysinfoScriptPath);
        lockScreenUi.wallpaperResolveNonce++;
    }

    ServiceRef { service: Cpu }
    ServiceRef { service: Memory }
    ServiceRef { service: Storage }
    ServiceRef { service: Weather }

    Timer {
        id: readyTimer

        interval: 50
        running: true
        onTriggered: lockScreenUi.ready = true
    }

    Plasma5Support.DataSource {
        id: schemeLoader

        engine: "executable"
        connectedSources: ["cat ~/.local/state/caelestia/scheme.json 2>/dev/null"]
        onNewData: (source, data) => {
            var stdout = data["stdout"] || "";
            disconnectSource(source);
            if (!stdout) return;
            try {
                var d = JSON.parse(stdout);
                var c = d.colours || d;
                if (c.surface) clSurface = "#" + c.surface;
                if (c.onSurface) clSurfaceFg = "#" + c.onSurface;
                if (c.surfaceContainer) clSurfaceContainer = "#" + c.surfaceContainer;
                if (c.surfaceContainerHigh) clSurfaceContainerHigh = "#" + c.surfaceContainerHigh;
                if (c.surfaceContainerHighest) clSurfaceContainerHighest = "#" + c.surfaceContainerHighest;
                if (c.primary) clPrimary = "#" + c.primary;
                if (c.secondary) clSecondary = "#" + c.secondary;
                if (c.onPrimary) clPrimaryFg = "#" + c.onPrimary;
                if (c.error) clError = "#" + c.error;
                if (c.onSurfaceVariant) clSurfaceVariantFg = "#" + c.onSurfaceVariant;
                if (c.primaryContainer) clPrimaryContainer = "#" + c.primaryContainer;
                if (c.secondaryContainer) clSecondaryContainer = "#" + c.secondaryContainer;
                if (c.tertiary) clTertiary = "#" + c.tertiary;
                if (c.onTertiary) clOnTertiary = "#" + c.onTertiary;
                if (c.outline) clOutline = "#" + c.outline;
                var terms = [];
                for (var i = 0; i < 8; i++) {
                    if (c["term" + i]) terms.push("#" + c["term" + i]);
                }
                if (terms.length > 0) lockScreenUi.clTerms = terms;
                lockScreenUi.greetingInfo = lockScreenUi.getGreeting();
            } catch(e) {}
        }
    }

    Plasma5Support.DataSource {
        id: configLoader

        engine: "executable"
        connectedSources: ["cat ~/.config/caelestia/shell.json 2>/dev/null"]
        onNewData: (source, data) => {
            var stdout = data["stdout"] || "";
            disconnectSource(source);
            if (!stdout) return;
            try {
                var cfg = JSON.parse(stdout);
                var svc = cfg.services || {};
                if (typeof svc.useTwelveHourClock === "boolean")
                    lockScreenUi.use12h = svc.useTwelveHourClock;

                if (typeof cfg.caelestiaMode === "boolean")
                    lockScreenUi.isCaelestiaMode = cfg.caelestiaMode;
                else if (typeof svc.caelestiaMode === "boolean")
                    lockScreenUi.isCaelestiaMode = svc.caelestiaMode;
                else if (cfg.general && typeof cfg.general.caelestiaMode === "boolean")
                    lockScreenUi.isCaelestiaMode = cfg.general.caelestiaMode;

                var lk = cfg.lock || {};
                if (typeof lk.recolourLogo === "boolean")
                    lockScreenUi.recolourLogo = lk.recolourLogo;
                if (typeof lk.hideNotifs === "boolean")
                    lockScreenUi.hideNotifs = lk.hideNotifs;
                if (typeof lk.enableFprint === "boolean")
                    lockScreenUi.enableFprint = lk.enableFprint;
                if (typeof lk.maxFprintTries === "number")
                    lockScreenUi.maxFprintTries = lk.maxFprintTries;
                if (typeof lk.profilePicShape === "number")
                    lockScreenUi.profilePicShape = lk.profilePicShape;
                if (typeof lk.rotateProfilePic === "boolean")
                    lockScreenUi.rotateProfilePic = lk.rotateProfilePic;
                if (typeof lk.blurWallpaper === "boolean")
                    lockScreenUi.blurWallpaper = lk.blurWallpaper;
                if (cfg.session && cfg.session.icons)
                    lockScreenUi.sessionIcons = cfg.session.icons;
                if (typeof lk.showSleep === "boolean")
                    lockScreenUi.showSleep = lk.showSleep;
                if (typeof lk.showHibernate === "boolean")
                    lockScreenUi.showHibernate = lk.showHibernate;
                if (typeof lk.showSwitchUser === "boolean")
                    lockScreenUi.showSwitchUser = lk.showSwitchUser;
                if (typeof lk.showLogout === "boolean")
                    lockScreenUi.showLogout = lk.showLogout;
                if (typeof lk.showReboot === "boolean")
                    lockScreenUi.showReboot = lk.showReboot;
                if (typeof lk.showShutdown === "boolean")
                    lockScreenUi.showShutdown = lk.showShutdown;
            } catch(e) {}
        }
    }

    Plasma5Support.DataSource {
        id: fetchLoader

        property var fetchInfo: null

        engine: "executable"
        connectedSources: ["python3 " + lockScreenUi.sysinfoScriptPath]
        onNewData: (source, data) => {
            var stdout = data["stdout"] || "";
            disconnectSource(source);
            if (!stdout) return;
            try {
                fetchInfo = JSON.parse(stdout);
            } catch(e) {}
        }
    }

    Plasma5Support.DataSource {
        id: mprisSource

        function poll() {
            connectSource("PATH=\"${CAELESTIA_BIN_DIR:-$HOME/.local/bin}:$PATH\" python3 -c 'import json, subprocess, os; ipc = \"caelestia-shell-ipc\"; get = lambda p: subprocess.run([ipc, \"call\", \"mpris\", \"getActive\", p], capture_output=True, text=True).stdout.strip(); t, a, u, s = get(\"trackTitle\"), get(\"trackArtist\"), get(\"trackArtUrl\"), get(\"playbackState\"); t = \"\" if t == \"No active player\" else t; print(json.dumps({\"title\": t, \"artist\": a, \"artUrl\": u, \"status\": \"Playing\" if s == \"1\" else \"Paused\"}))'");
        }

        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            var stdout = data["stdout"] || "";
            disconnectSource(source);
            if (!stdout) return;
            try {
                var info = JSON.parse(stdout);
                if (info && typeof info === "object") {
                    lockScreenUi.liveMedia = info;
                }
            } catch(e) {}
        }
    }

    Timer {
        id: mprisTimer

        property double lastTick: 0

        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            // A tick that lands far late means the greeter was frozen through a
            // suspend: timers stop while the machine sleeps, so the gap is the
            // resume signal the host does not give the theme (issue #815).
            var now = Date.now();
            if (mprisTimer.lastTick > 0 && now - mprisTimer.lastTick > 10000)
                lockScreenUi.rearmAfterResume();
            mprisTimer.lastTick = now;
            mprisSource.poll()
        }
    }

    Plasma5Support.DataSource {
        id: mediaActionSource

        readonly property var actionCmds: ({
            "previous":  lockScreenUi.ipcBin + " call mpris previous",
            "playPause": lockScreenUi.ipcBin + " call mpris playPause",
            "next":      lockScreenUi.ipcBin + " call mpris next"
        })

        function send(action) {
            var cmd = actionCmds[action];
            if (cmd) connectSource(cmd);
        }

        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            mprisSource.poll();
        }
    }

    Plasma5Support.DataSource {
        id: notifLoader

        function poll() {
            connectSource("cat ~/.local/state/caelestia/notifs.json 2>/dev/null");
        }

        engine: "executable"
        connectedSources: ["cat ~/.local/state/caelestia/notifs.json 2>/dev/null"]
        onNewData: (source, data) => {
            var stdout = data["stdout"] || "";
            disconnectSource(source);
            if (!stdout) return;
            if (lockScreenUi.isClearingNotifs) return;
            try {
                var arr = JSON.parse(stdout);
                if (Array.isArray(arr)) {
                    if (lockScreenUi.notifsClearedAt > 0) {
                        arr = arr.filter(function(n) {
                            if (!n || !n.time) return false;
                            var t = new Date(n.time).getTime();
                            return !isNaN(t) && t > lockScreenUi.notifsClearedAt;
                        });
                    }
                    lockScreenUi.liveNotifs = arr;
                }
            } catch(e) {}
        }
    }

    Timer {
        id: notifTimer

        interval: 3000
        repeat: true
        running: true
        onTriggered: notifLoader.poll()
    }

    Plasma5Support.DataSource {
        id: notifActionSource

        function clearAll() {
            lockScreenUi.notifsClearedAt = Date.now();
            lockScreenUi.liveNotifs = [];
            lockScreenUi.isClearingNotifs = true;
            connectSource(lockScreenUi.ipcBin + " call notifs clear");
        }

        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            lockScreenUi.isClearingNotifs = false;
            notifLoader.poll();
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: lockScreenUi.greetingInfo = lockScreenUi.getGreeting()
    }

    AuthHandler {
        id: authHandler

        authenticatorTarget: (typeof authenticator !== "undefined") ? authenticator : null
        maxFprintTries: lockScreenUi.maxFprintTries
        onShakeRequested: if (activePasswordPill) activePasswordPill.shake()
        onFocusSecretRequested: if (activePasswordPill) activePasswordPill.forceActiveFocus()
        onSucceeded: {
            Qt.quit();
        }
        onMessageChanged: msg => {
            if (msg) {
                msgExitAnim.stop();
                var wasEmpty = !lockScreenUi.authMessage;
                lockScreenUi.authMessage = msg;
                var isVisible = lockScreenUi.isPortrait ? (portraitErrorText && portraitErrorText.visible) : (errorText && errorText.visible);
                if (wasEmpty || !isVisible) {
                    msgAppearAnim.restart();
                }
            } else {
                msgAppearAnim.stop();
                msgFlashAnim.stop();
                msgExitAnim.start();
            }
        }
        onClearPasswordRequested: {
            if (passwordPill) passwordPill.clearPassword();
            if (portraitPasswordPill) portraitPasswordPill.clearPassword();
            if (typeof root !== "undefined" && typeof root.clearPassword === "function") root.clearPassword();
        }
        onNotificationRepeated: {
            msgExitAnim.stop();
            msgFlashAnim.restart();
            if (activePasswordPill) activePasswordPill.shake();
            if (typeof root !== "undefined" && typeof root.notificationRepeated === "function") root.notificationRepeated();
        }
    }

    SessionManagement {
        id: sessionManagement
    }

    KeyboardIndicator.KeyState {
        id: capsLockState

        key: Qt.Key_CapsLock
    }

    Connections {
        function onAboutToSuspend() { root.clearPassword(); }

        target: sessionManagement
    }

    Connections {
        function onClearPassword() {
            if (passwordPill) passwordPill.clearPassword();
            if (portraitPasswordPill) portraitPasswordPill.clearPassword();
        }

        function onViewVisibleChanged() {
            // The host raises viewVisible when the greeter is shown, including again
            // after a resume, which is when the one-shot data above is stale.
            if (root.viewVisible)
                lockScreenUi.rearmAfterResume();
        }

        target: root
    }

    SequentialAnimation {
        id: msgAppearAnim

        onFinished: msgFlashAnim.start()

        PropertyAction { target: errorText; property: "visible"; value: true }
        PropertyAction { target: portraitErrorText; property: "visible"; value: true }

        ParallelAnimation {
            NumberAnimation { target: errorText; property: "scale"; from: 0.7; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: errorText; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: portraitErrorText; property: "scale"; from: 0.7; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: portraitErrorText; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
        }
    }

    SequentialAnimation {
        id: msgFlashAnim

        loops: 2

        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: errorText; property: "opacity"; to: 0.3; duration: 150 }
                NumberAnimation { target: errorText; property: "opacity"; to: 1; duration: 150 }
            }

            SequentialAnimation {
                NumberAnimation { target: portraitErrorText; property: "opacity"; to: 0.3; duration: 150 }
                NumberAnimation { target: portraitErrorText; property: "opacity"; to: 1; duration: 150 }
            }
        }
    }

    SequentialAnimation {
        id: msgExitAnim

        onFinished: {
            lockScreenUi.authMessage = "";
            if (typeof root !== "undefined" && typeof root.notification !== "undefined") {
                root.notification = "";
            }
        }

        ParallelAnimation {
            NumberAnimation { target: errorText; property: "scale"; to: 0.7; duration: 400; easing.type: Easing.InOutQuad }
            NumberAnimation { target: errorText; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InOutQuad }
            NumberAnimation { target: portraitErrorText; property: "scale"; to: 0.7; duration: 400; easing.type: Easing.InOutQuad }
            NumberAnimation { target: portraitErrorText; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InOutQuad }
        }

        PropertyAction { target: errorText; property: "visible"; value: false }
        PropertyAction { target: portraitErrorText; property: "visible"; value: false }
    }

    FastBlur {
        id: wallpaperBlur

        anchors.fill: parent
        // The wallpaper item belongs to the greeter host and can be missing around a
        // suspend; resolving it to null blanks the blur for the rest of the lock. The
        // nonce makes the lookup happen again whenever a resume is detected
        // (issue #815).
        source: {
            lockScreenUi.wallpaperResolveNonce;
            return (typeof wallpaper !== "undefined" && wallpaper) ? wallpaper : null;
        }
        radius: 64
        visible: false
    }

    Item {
        id: fullWallpaperBlurOverlay

        anchors.fill: parent
        visible: lockScreenUi.blurWallpaper
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 250 }
        }

        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: wallpaperBlur
            live: true
        }
    }

    FocusScope {
        id: lockScreenRoot

        anchors.fill: parent
        focus: true
        opacity: lockScreenUi.ready ? 1.0 : 0.0

        Keys.onPressed: event => {
            authHandler.ensureAuthenticating();
            if (activePasswordPill) activePasswordPill.forceActiveFocus();
            event.accepted = false;
        }
        Keys.onEscapePressed: {
            authHandler.ensureAuthenticating();
            root.clearPassword();
        }

        Component.onCompleted: authHandler.ensureAuthenticating()

        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onPositionChanged: authHandler.ensureAuthenticating()
            onPressed: mouse => {
                authHandler.ensureAuthenticating();
                if (activePasswordPill) activePasswordPill.forceActiveFocus();
                mouse.accepted = false;
            }
        }

        Item {
            Timer {
                property int n: 0

                interval: 300
                repeat: true
                running: true
                onTriggered: {
                    if (activePasswordPill) activePasswordPill.forceActiveFocus();
                    if (++n >= 10) repeat = false;
                }
            }
        }

        Item {
            id: landscapeContent

            readonly property real innerHeight: height - 2 * lockScreenUi.bgMargin
            readonly property real colSpacing: 16 * lockScreenUi.centerScale
            readonly property real leftCardPool: innerHeight - 2 * colSpacing
            readonly property real rightCardPool: innerHeight - 1 * colSpacing

            readonly property real centerSpacing: innerHeight >= 680
                ? Math.round(18 * lockScreenUi.centerScale)
                : (innerHeight >= 560 ? Math.round(10 * lockScreenUi.centerScale) : Math.max(6, Math.round(8 * lockScreenUi.centerScale)))
            readonly property real avatarHeightRatio: innerHeight >= 680 ? 0.36 : (innerHeight >= 560 ? 0.30 : 0.24)
            readonly property real avatarWidthRatio: innerHeight >= 680 ? 0.85 : (innerHeight >= 560 ? 0.75 : 0.60)
            readonly property real avatarSize: Math.min(lockScreenUi.centerWidth * avatarWidthRatio, innerHeight * avatarHeightRatio)
            readonly property real avatarMargin: innerHeight >= 680 ? Math.max(6, 8 * lockScreenUi.centerScale) : (innerHeight >= 560 ? 4 : 2)
            readonly property real centerItemMargin: innerHeight >= 680 ? Math.max(4, 6 * lockScreenUi.centerScale) : (innerHeight >= 560 ? 2 : 0)

            anchors.centerIn: parent
            width: lockScreenUi.lockLong
            height: lockScreenUi.lockShort
            visible: !lockScreenUi.isPortrait
            clip: true

            Behavior on height {
                enabled: lockScreenUi.ready

                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }

            Item {
                anchors.fill: lockBg
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: lockBg.width; height: lockBg.height; radius: lockBg.radius }
                }

                ShaderEffectSource {
                    anchors.fill: parent
                    sourceItem: wallpaperBlur
                    sourceRect: Qt.rect(landscapeContent.x, landscapeContent.y, landscapeContent.width, landscapeContent.height)
                    live: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(lockScreenUi.clSurface.r, lockScreenUi.clSurface.g, lockScreenUi.clSurface.b, 0.50)
                }
            }

            Rectangle {
                id: lockBg

                anchors.fill: parent
                color: "transparent"
                border.color: Qt.rgba(lockScreenUi.clSurfaceVariantFg.r, lockScreenUi.clSurfaceVariantFg.g, lockScreenUi.clSurfaceVariantFg.b, 0.12)
                border.width: 1
                radius: lockScreenUi.bgRadius
            }

            RowLayout {
                id: landscapeLayout

                anchors.fill: parent
                anchors.margins: lockScreenUi.bgMargin
                spacing: 40 * (lockScreenUi.lockHeight / 1080)

                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: landscapeContent.colSpacing

                    WeatherCard {
                        id: weatherCard

                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(landscapeContent.leftCardPool * 0.18)
                        implicitHeight: Layout.preferredHeight
                        cardRadius: lockScreenUi.cardRadius
                        centerScale: lockScreenUi.centerScale
                        clSurfaceContainer: lockScreenUi.clCardBg
                        clSurfaceFg: lockScreenUi.clSurfaceFg
                        clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                        clPrimary: lockScreenUi.clPrimary
                    }

                    CaelestiafetchCard {
                        id: fetchCard

                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(landscapeContent.leftCardPool * 0.35)
                        implicitHeight: Layout.preferredHeight
                        cardRadius: lockScreenUi.cardRadius
                        centerScale: lockScreenUi.centerScale
                        fetchInfo: fetchLoader.fetchInfo
                        clTerms: lockScreenUi.clTerms
                        recolourLogo: lockScreenUi.recolourLogo
                        clSurface: lockScreenUi.clSurface
                        clSurfaceContainer: lockScreenUi.clCardBg
                        clSurfaceContainerHigh: lockScreenUi.clCardBgHigh
                        clSurfaceContainerHighest: lockScreenUi.clSurfaceContainerHighest
                        clSurfaceFg: lockScreenUi.clSurfaceFg
                        clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                        clPrimary: lockScreenUi.clPrimary
                    }

                    MediaCard {
                        id: mediaCard

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: Math.max(0, landscapeContent.leftCardPool - weatherCard.Layout.preferredHeight - fetchCard.Layout.preferredHeight)
                        implicitHeight: Layout.preferredHeight
                        cardRadius: lockScreenUi.cardRadius
                        centerScale: lockScreenUi.centerScale
                        mediaInfo: lockScreenUi.liveMedia
                        clSurface: lockScreenUi.clSurface
                        clSurfaceContainer: lockScreenUi.clCardBg
                        clSurfaceFg: lockScreenUi.clSurfaceFg
                        clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                        clPrimary: lockScreenUi.clPrimary
                        onPreviousRequested: mediaActionSource.send("previous")
                        onPlayPauseRequested: mediaActionSource.send("playPause")
                        onNextRequested: mediaActionSource.send("next")
                    }
                }

                Item {
                    id: centerColumnArea

                    Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                    Layout.preferredWidth: lockScreenUi.centerWidth
                    Layout.fillWidth: false
                    Layout.fillHeight: true

                    ColumnLayout {
                        id: centerMainColumn

                        anchors.centerIn: parent
                        width: parent.width
                        spacing: landscapeContent.centerSpacing

                        ClockWidget {
                            Layout.alignment: Qt.AlignHCenter
                            use12h: lockScreenUi.use12h
                            centerScale: lockScreenUi.centerScale
                            clPrimary: lockScreenUi.clPrimary
                            clSecondary: lockScreenUi.clSecondary
                            clSurfaceContainerHigh: lockScreenUi.clCardBgHigh
                            clSurfaceFg: lockScreenUi.clSurfaceFg
                            clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                        }

                        ProfileAvatar {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: landscapeContent.avatarMargin
                            Layout.bottomMargin: landscapeContent.avatarMargin
                            implicitWidth: landscapeContent.avatarSize
                            implicitHeight: landscapeContent.avatarSize
                            Layout.preferredWidth: implicitWidth
                            Layout.preferredHeight: implicitHeight
                            centerScale: lockScreenUi.centerScale
                            profileShape: lockScreenUi.profilePicShape
                            rotateShape: lockScreenUi.rotateProfilePic
                            userImage: (typeof kscreenlocker_userImage !== "undefined" && kscreenlocker_userImage) ? kscreenlocker_userImage.toString() : ""
                            userName: typeof kscreenlocker_userName !== "undefined" ? kscreenlocker_userName : ""
                            clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                            clSurfaceContainerHighest: lockScreenUi.clSurfaceContainerHighest
                        }

                        GreetingPill {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.bottomMargin: landscapeContent.centerItemMargin
                            centerScale: lockScreenUi.centerScale
                            centerWidth: lockScreenUi.centerWidth
                            greetingInfo: lockScreenUi.greetingInfo
                            userName: typeof kscreenlocker_userName !== "undefined" ? kscreenlocker_userName : "User"
                            clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                            clPrimary: lockScreenUi.clPrimary
                        }

                        PasswordPill {
                            id: passwordPill

                            Layout.alignment: Qt.AlignHCenter
                            centerScale: lockScreenUi.centerScale
                            centerWidth: lockScreenUi.centerWidth
                            pillWidth: lockScreenUi.passwordPillWidth
                            focus: !lockScreenUi.isPortrait
                            isAuthenticating: lockScreenUi.isAuthenticating
                            graceLocked: authHandler.graceLocked
                            lockoutActive: authHandler.lockoutActive
                            lockoutText: authHandler.lockoutText
                            hasFingerprint: lockScreenUi.hasFingerprint
                            fprintDisabledDueToTries: lockScreenUi.fprintDisabledDueToTries
                            clError: lockScreenUi.clError
                            clSurfaceContainer: lockScreenUi.clCardBg
                            clSurfaceContainerHigh: lockScreenUi.clCardBgHigh
                            clSurfaceFg: lockScreenUi.clSurfaceFg
                            clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                            clPrimary: lockScreenUi.clPrimary
                            clPrimaryFg: lockScreenUi.clPrimaryFg
                            onLoginRequested: pass => lockScreenUi.startLogin(pass)
                        }

                        Session {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: landscapeContent.centerItemMargin
                            centerScale: lockScreenUi.centerScale
                            isAuthenticating: lockScreenUi.isAuthenticating
                            clPrimary: lockScreenUi.clPrimary
                            clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                            sessionManagement: sessionManagement
                            customIcons: lockScreenUi.sessionIcons
                            showSleep: lockScreenUi.showSleep
                            showHibernate: lockScreenUi.showHibernate
                            showSwitchUser: lockScreenUi.showSwitchUser
                            showLogout: lockScreenUi.showLogout
                            showReboot: lockScreenUi.showReboot
                            showShutdown: lockScreenUi.showShutdown
                        }
                    }

                    Item {
                        id: landscapeStatusContainer

                        readonly property bool hasStatus: (capsLockState.locked && !lockScreenUi.authMessage) || Boolean(lockScreenUi.authMessage) || lockScreenUi.hasFingerprint

                        anchors.top: centerMainColumn.bottom
                        anchors.topMargin: landscapeContent.innerHeight >= 680 ? 6 : 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        height: hasStatus ? Math.max(14, statusCol.implicitHeight) : 0
                        visible: hasStatus

                        Column {
                            id: statusCol

                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            spacing: 4 * lockScreenUi.centerScale

                            Text {
                                id: capsText

                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                visible: capsLockState.locked && !lockScreenUi.authMessage
                                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on")
                                font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody }
                                color: lockScreenUi.clSurfaceVariantFg
                                wrapMode: Text.WordWrap
                                opacity: visible ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: 300 }
                                }
                            }

                            Text {
                                id: errorText

                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                visible: false
                                text: lockScreenUi.authMessage
                                font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody }
                                color: lockScreenUi.clError
                                wrapMode: Text.WordWrap
                                scale: 0.7
                                opacity: 0
                            }

                            Text {
                                id: fpHint

                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                visible: lockScreenUi.hasFingerprint
                                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your fingerprint on the reader)")
                                font { pixelSize: LockScreenConfig.sizeVerySmall; family: LockScreenConfig.fontBody }
                                color: lockScreenUi.clSurfaceVariantFg
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: landscapeContent.colSpacing

                    ResourcesCard {
                        id: resourcesCard

                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(landscapeContent.rightCardPool * 0.23)
                        implicitHeight: Layout.preferredHeight
                        cardRadius: lockScreenUi.cardRadius
                        centerScale: lockScreenUi.centerScale
                        liveCpu: lockScreenUi.liveCpu
                        liveTemp: lockScreenUi.liveTemp
                        liveRam: lockScreenUi.liveRam
                        liveDisk: lockScreenUi.liveDisk
                        cpuPercentage: Cpu.percentage ?? 0
                        memoryPercentage: Memory.percentage ?? 0
                        storagePercentage: Storage.percentage ?? 0
                        clSurface: lockScreenUi.clSurface
                        clSurfaceContainer: lockScreenUi.clCardBg
                        clSurfaceContainerHigh: lockScreenUi.clCardBgHigh
                        clSurfaceContainerHighest: lockScreenUi.clSurfaceContainerHighest
                        clPrimaryContainer: lockScreenUi.clPrimaryContainer
                        clSecondaryContainer: lockScreenUi.clSecondaryContainer
                        clTertiary: lockScreenUi.clTertiary
                        clOnTertiary: lockScreenUi.clOnTertiary
                        clOutline: lockScreenUi.clOutline
                        clSurfaceFg: lockScreenUi.clSurfaceFg
                        clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                        clPrimary: lockScreenUi.clPrimary
                        clSecondary: lockScreenUi.clSecondary
                        clError: lockScreenUi.clError
                    }

                    NotifDock {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: Math.max(0, landscapeContent.rightCardPool - resourcesCard.Layout.preferredHeight)
                        cardRadius: lockScreenUi.cardRadius
                        centerScale: lockScreenUi.centerScale
                        liveNotifs: lockScreenUi.liveNotifs
                        isCaelestiaMode: lockScreenUi.isCaelestiaMode
                        hideNotifs: lockScreenUi.hideNotifs
                        clSurfaceContainer: lockScreenUi.clCardBg
                        clSurfaceContainerHigh: lockScreenUi.clCardBgHigh
                        clSurfaceContainerHighest: lockScreenUi.clSurfaceContainerHighest
                        clSecondaryContainer: lockScreenUi.clSecondaryContainer
                        clSurfaceFg: lockScreenUi.clSurfaceFg
                        clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                        clOutline: lockScreenUi.clOutline
                        onClearAllRequested: notifActionSource.clearAll()
                    }
                }
            }
        }

        // TODO: re-instantiates ClockWidget, ProfileAvatar, GreetingPill and PasswordPill
        Item {
            id: portraitContent

            anchors.centerIn: parent
            width: Math.min(parent.width * 0.9, lockScreenUi.lockShort)
            height: portraitLayout.implicitHeight + 64 * lockScreenUi.centerScale
            visible: lockScreenUi.isPortrait
            clip: true

            Behavior on height {
                enabled: lockScreenUi.ready

                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }

            Item {
                anchors.fill: portraitBg
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: portraitBg.width; height: portraitBg.height; radius: lockScreenUi.bgRadius }
                }

                ShaderEffectSource {
                    anchors.fill: parent
                    sourceItem: wallpaperBlur
                    sourceRect: Qt.rect(portraitContent.x, portraitContent.y, portraitContent.width, portraitContent.height)
                    live: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(lockScreenUi.clSurface.r, lockScreenUi.clSurface.g, lockScreenUi.clSurface.b, 0.50)
                }
            }

            Rectangle {
                id: portraitBg

                anchors.fill: parent
                color: "transparent"
                border.color: Qt.rgba(lockScreenUi.clSurfaceVariantFg.r, lockScreenUi.clSurfaceVariantFg.g, lockScreenUi.clSurfaceVariantFg.b, 0.12)
                border.width: 1
                radius: lockScreenUi.bgRadius
            }

            ColumnLayout {
                id: portraitLayout

                anchors.centerIn: parent
                width: parent.width - 48 * lockScreenUi.centerScale
                spacing: 20 * lockScreenUi.centerScale

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    spacing: 24 * lockScreenUi.centerScale

                    ProfileAvatar {
                        Layout.preferredWidth: lockScreenUi.centerWidth * 0.4
                        Layout.preferredHeight: Layout.preferredWidth
                        centerScale: lockScreenUi.centerScale
                        profileShape: lockScreenUi.profilePicShape
                        rotateShape: lockScreenUi.rotateProfilePic
                        userImage: (typeof kscreenlocker_userImage !== "undefined" && kscreenlocker_userImage) ? kscreenlocker_userImage.toString() : ""
                        userName: typeof kscreenlocker_userName !== "undefined" ? kscreenlocker_userName : ""
                        clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                        clSurfaceContainerHighest: lockScreenUi.clSurfaceContainerHighest
                    }

                    ClockWidget {
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                        use12h: lockScreenUi.use12h
                        centerScale: lockScreenUi.centerScale
                        clPrimary: lockScreenUi.clPrimary
                        clSecondary: lockScreenUi.clSecondary
                        clSurfaceContainerHigh: lockScreenUi.clCardBgHigh
                        clSurfaceFg: lockScreenUi.clSurfaceFg
                        clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                    }
                }

                GreetingPill {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 8 * lockScreenUi.centerScale
                    centerScale: lockScreenUi.centerScale
                    centerWidth: lockScreenUi.centerWidth
                    greetingInfo: lockScreenUi.greetingInfo
                    userName: typeof kscreenlocker_userName !== "undefined" ? kscreenlocker_userName : "User"
                    pillColor: lockScreenUi.clCardBg
                    clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                    clPrimary: lockScreenUi.clPrimary
                }

                PasswordPill {
                    id: portraitPasswordPill

                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8 * lockScreenUi.centerScale
                    Layout.bottomMargin: 8 * lockScreenUi.centerScale
                    centerScale: lockScreenUi.centerScale
                    centerWidth: lockScreenUi.centerWidth
                    pillWidth: lockScreenUi.passwordPillWidth
                    focus: lockScreenUi.isPortrait
                    isAuthenticating: lockScreenUi.isAuthenticating
                    graceLocked: authHandler.graceLocked
                    lockoutActive: authHandler.lockoutActive
                    lockoutText: authHandler.lockoutText
                    hasFingerprint: lockScreenUi.hasFingerprint
                    fprintDisabledDueToTries: lockScreenUi.fprintDisabledDueToTries
                    clError: lockScreenUi.clError
                    clSurfaceContainer: lockScreenUi.clCardBg
                    clSurfaceContainerHigh: lockScreenUi.clCardBgHigh
                    clSurfaceFg: lockScreenUi.clSurfaceFg
                    clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                    clPrimary: lockScreenUi.clPrimary
                    clPrimaryFg: lockScreenUi.clPrimaryFg
                    onLoginRequested: pass => lockScreenUi.startLogin(pass)
                }

                Session {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4 * lockScreenUi.centerScale
                    Layout.bottomMargin: 4 * lockScreenUi.centerScale
                    centerScale: lockScreenUi.centerScale
                    isAuthenticating: lockScreenUi.isAuthenticating
                    clPrimary: lockScreenUi.clPrimary
                    clSurfaceVariantFg: lockScreenUi.clSurfaceVariantFg
                    sessionManagement: sessionManagement
                    customIcons: lockScreenUi.sessionIcons
                    showSleep: lockScreenUi.showSleep
                    showHibernate: lockScreenUi.showHibernate
                    showSwitchUser: lockScreenUi.showSwitchUser
                    showLogout: lockScreenUi.showLogout
                    showReboot: lockScreenUi.showReboot
                    showShutdown: lockScreenUi.showShutdown
                }

                Item {
                    id: portraitStatusContainer

                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64 * lockScreenUi.centerScale
                    implicitHeight: Layout.preferredHeight
                    Layout.topMargin: 4 * lockScreenUi.centerScale
                    Layout.bottomMargin: 8 * lockScreenUi.centerScale

                    Column {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        spacing: 4 * lockScreenUi.centerScale

                        Text {
                            id: portraitCapsText

                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            visible: capsLockState.locked && !lockScreenUi.authMessage
                            text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on")
                            font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody }
                            color: lockScreenUi.clSurfaceVariantFg
                            wrapMode: Text.WordWrap
                            opacity: visible ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation { duration: 300 }
                            }
                        }

                        Text {
                            id: portraitErrorText

                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            visible: false
                            text: lockScreenUi.authMessage
                            font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody }
                            color: lockScreenUi.clError
                            wrapMode: Text.WordWrap
                            scale: 0.7
                            opacity: 0
                        }

                        Text {
                            id: portraitFpHint

                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            visible: lockScreenUi.hasFingerprint
                            text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your fingerprint on the reader)")
                            font { pixelSize: LockScreenConfig.sizeVerySmall; family: LockScreenConfig.fontBody }
                            color: lockScreenUi.clSurfaceVariantFg
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            RowLayout {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: Kirigami.Units.smallSpacing }
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.ToolButton {
                    icon.name: "input-keyboard"
                    text: kls.layoutNames.longName
                    visible: kls.hasMultipleKeyboardLayouts
                    Layout.fillHeight: true
                    onClicked: kls.keyboardLayout.switchToNextLayout()

                    PW.KeyboardLayoutSwitcher {
                        id: kls

                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }

    Binding { target: root; property: "viewVisible"; value: true }
}
