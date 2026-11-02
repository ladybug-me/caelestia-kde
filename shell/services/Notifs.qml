pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Caelestia
import Caelestia.Config
import qs.components.misc
import qs.services
import qs.utils
import "notifquery.js" as NotifQuery

Singleton {
    id: root

    property list<NotifData> list: []
    property int openCount: 0
    property int popupCount: 0

    readonly property int notifCap: Math.max(1, GlobalConfig.notifs.maxNotifs)

    /// The user's own switch, and the only thing the toggle surfaces write.
    property alias dnd: props.dnd
    /// Why another feature wants quiet: a game, a focus session, a stream. Reasons are
    /// named so they cannot clobber one another, and none of them touch `dnd`.
    property var dndHolders: ({})
    /// What popups, sounds and the indicators read: quiet for any reason at all.
    readonly property bool quiet: props.dnd || Object.keys(root.dndHolders).length > 0
    property string lastSavedState: ""
    property string activeTargetOutput: ""
    property bool loaded

    /// Claim or release a named reason to stay quiet. Idempotent, so callers can call it
    /// on every state change instead of remembering whether they already hold.
    function setDndHold(reason: string, held: bool): void {
        if (reason === "" || (reason in root.dndHolders) === held)
            return;

        const next = Object.assign({}, root.dndHolders);
        if (held)
            next[reason] = true;
        else
            delete next[reason];

        root.dndHolders = next;
    }

    function getCursorOutputName(): string {
        const monitor = Kwin.monitors.find(m => m.name === Kwin.cursorOutputName()) || Kwin.focusedMonitor;
        return monitor?.name || Kwin.cursorOutputName() || "";
    }

    function getTargetOutput(): string {
        const cursorScreen = root.getCursorOutputName();
        if (GlobalConfig.notifs.monitor === "focused") {
            if (GlobalConfig.notifs.fullscreen === "off" && Kwin.hasFullscreenOn(cursorScreen)) {
                const scrList = Screens.screens || [];
                for (let i = 0; i < scrList.length; i++) {
                    const candidate = scrList[i].name;
                    if (candidate !== cursorScreen && !Kwin.hasFullscreenOn(candidate))
                        return candidate;
                }
                return "";
            }
            return cursorScreen;
        }
        return cursorScreen;
    }

    function hasFullscreen(): bool {
        return Kwin.hasFullscreen();
    }

    // Called only when an actual list of items is needed (serialisation, clear).
    // Not used as a binding anywhere.
    function notClosed(): list<NotifData> { return list.filter(n => !n.closed) }

    /// Files a freshly created notification: counts it, puts it at the top of the
    /// list and evicts whatever the cap pushes out. Both the D-Bus path below and
    /// the shell-authored path go through here so the cap policy lives once.
    function registerNotification(comp: NotifData): void {
        root.openCount++;
        if (comp.popup)
            root.popupCount++;

        const next = [comp, ...root.list];
        const cap = root.notifCap;
        if (next.length > cap) {
            const evicted = next.splice(cap);
            for (const old of evicted) old.close();
        }
        root.list = next;
    }

    /// Raises a notification the shell authored itself: there is no D-Bus
    /// notification behind it, and its actions run shell callbacks rather than
    /// the sender's. Kept out of the on-disk history, since those callbacks
    /// cannot survive a restart (see NotifData.shellRaised).
    function addShellNotification(params: var): NotifData {
        // The same bookkeeping the D-Bus path does: which screen a popup belongs to
        // is settled before it is created, because shouldShowPopup() reads it.
        root.activeTargetOutput = root.getTargetOutput();

        const comp = notifComp.createObject(root, {
            popup: root.shouldShowPopup(params.appName ?? ""),
            shellRaised: true,
            image: "",
            hints: ({}),
            appName: params.appName ?? qsTr("Caelestia"),
            summary: params.summary ?? "",
            body: params.body ?? "",
            appIcon: params.appIcon ?? "",
            materialIcon: params.materialIcon ?? "",
            actions: params.actions ?? [],
            resident: params.resident ?? true
        });

        root.registerNotification(comp);

        return comp;
    }

    /// Whether this app's notifications are turned off entirely.
    function isMuted(appName: string): bool {
        return GlobalConfig.notifs.mutedApps.includes(appName);
    }

    /// Turns an app's notifications off and drops what is already in the list: the
    /// answer has to be visible immediately, or the next banner looks like the mute
    /// did not stick.
    function muteApp(appName: string): void {
        if (appName === "")
            return;

        if (!root.isMuted(appName)) {
            GlobalConfig.notifs.mutedApps = Array.from(GlobalConfig.notifs.mutedApps).concat([appName]);
            GlobalConfig.save();
        }

        const dropped = root.list.filter(n => n.appName === appName);
        if (dropped.length === 0)
            return;

        root.list = root.list.filter(n => n.appName !== appName);
        // Closing is what keeps the count honest: NotifData reports its own close, so
        // decrementing here as well would count the same notification twice.
        for (const notif of dropped)
            notif.close();
    }

    function unmuteApp(appName: string): void {
        if (!root.isMuted(appName))
            return;

        GlobalConfig.notifs.mutedApps = Array.from(GlobalConfig.notifs.mutedApps).filter(name => name !== appName);
        GlobalConfig.save();
    }

    /// Whether a search for `query` should show this notification. The fields it reads
    /// are stated in notifquery.js, where a test can run them without a shell.
    function matchesQuery(notif: NotifData, query: string): bool {
        return NotifQuery.matches(notif.appName, notif.summaryPlain, notif.bodyPlain, query);
    }

    /// Whether this app's notification must stay quiet right now. Both the popup and
    /// the sound ask this, so the DND/focus policy and the fullscreen rule are stated
    /// once rather than copied into each decision.
    function isSilenced(appName: string): bool {
        if (root.isMuted(appName))
            return true;

        if (root.quiet && !Focus.allows(appName))
            return true;
        if (GlobalConfig.notifs.fullscreen !== "off")
            return false;

        if (GlobalConfig.notifs.monitor === "focused") {
            const targetName = root.activeTargetOutput || root.getTargetOutput();
            return targetName === "" || Kwin.hasFullscreenOn(targetName);
        }

        const scrList = Screens.screens || [];
        if (scrList.length > 0)
            return scrList.every(s => Kwin.hasFullscreenOn(s.name));

        return hasFullscreen();
    }

    function shouldShowPopup(appName: string): bool {
        if ([...Visibilities.screens.values()].some(v => v.sidebar))
            return false;

        return !root.isSilenced(appName);
    }

    function shouldPlaySound(notif: Notification): bool {
        if (notif.appName === "caelestia-cli" || GlobalConfig.audio.sounds.disabledNotifApps.includes(notif.appName))
            return false;

        return !root.isSilenced(notif.appName);
    }

    function clear(): void {
        const toClose = root.list;
        root.list = [];
        root.openCount = 0;
        root.popupCount = 0;
        for (let i = 0; i < toClose.length; i++)
            toClose[i].close();
        saveTimer.stop();
        root.lastSavedState = "[]";
        storage.setText("[]");
    }

    function toPlainList(): var {
        return root.notClosed().filter(n => !n.shellRaised).map(n => ({
                        time: n.time,
                        id: n.id,
                        summary: n.summary,
                        body: n.body,
                        appIcon: n.appIcon,
                        appName: n.appName,
                        image: n.image,
                        expireTimeout: n.expireTimeout,
                        urgency: n.urgency,
                        resident: n.resident,
                        hasActionIcons: n.hasActionIcons,
                        actions: n.actions
                    }));
    }

    function persistedJson(): string {
        return JSON.stringify(root.toPlainList());
    }

    onDndChanged: {
        if (!GlobalConfig.utilities.toasts.dndChanged)
            return;

        if (dnd)
            Toaster.toast(qsTr("Do not disturb enabled"), qsTr("Popup notifications are now disabled"), "do_not_disturb_on");
        else
            Toaster.toast(qsTr("Do not disturb disabled"), qsTr("Popup notifications are now enabled"), "do_not_disturb_off");
    }

    onListChanged: {
        if (loaded)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: Math.min(10000, 3000 + root.list.length * 10)
        onTriggered: {
            const serialized = root.persistedJson();
            if (serialized === root.lastSavedState)
                return;
            root.lastSavedState = serialized;
            storage.setText(serialized);
        }
    }

    PersistentProperties {
        id: props

        property bool dnd

        reloadableId: "notifs"
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true
        // Lets clients offer reply-from-the-notification. The shell answers it in
        // the sidebar dock; a passive toast cannot take keyboard focus.
        inlineReplySupported: true

        onNotification: notif => {
            notif.tracked = true;

            // A muted app is answered and dismissed rather than filed: the sender sees a
            // normal close, and the list, the unread count and the sound never see it.
            // No NotifData is built for it, because filing is what counts a
            // notification and this one is never filed.
            if (root.isMuted(notif.appName)) {
                notif.dismiss();
                return;
            }

            root.activeTargetOutput = root.getTargetOutput();

            const showPopup = root.shouldShowPopup(notif.appName);
            const comp = notifComp.createObject(root, {
                popup: showPopup,
                notification: notif
            });

            root.registerNotification(comp);

            if (root.shouldPlaySound(notif))
                Audio.playNotification();
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/notifs.json`
        onLoaded: {
            let data;
            try {
                data = JSON.parse(text());
            } catch (err) {
                Logger.log("[Notifs] saved notifications are corrupt, starting fresh:", err);
                data = [];
            }
            if (!Array.isArray(data)) {
                Logger.log("[Notifs] saved notifications are not a list, starting fresh");
                data = [];
            }
            data.sort((a, b) => b.time - a.time);
            const cap = root.notifCap;
            root.list = data.slice(0, cap).map(n => notifComp.createObject(root, n));

            root.openCount = root.list.filter(n => !n.closed).length;
            root.popupCount = root.list.filter(n => n.popup).length;
            root.lastSavedState = root.persistedJson();
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                root.lastSavedState = "[]";
                Qt.callLater(() => setText("[]"));
            }
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clearNotifs"
        description: qsTr("Clear all notifications")
        onPressed: root.clear()
    }

    IpcHandler {
        /// Live snapshot of the list plus the quiet state, for out-of-process views
        /// (the lock screen) that cannot read the in-process model. Same `toPlainList()`
        /// the persisted history uses, so both views describe the same notifications.
        function list(): string {
            return JSON.stringify({
                quiet: root.quiet,
                items: root.toPlainList()
            });
        }

        function clear(): void {
            root.clear();
        }

        /// The apps whose notifications are turned off, as JSON.
        function mutedApps(): string {
            return JSON.stringify(GlobalConfig.notifs.mutedApps);
        }

        function mute(appName: string): void {
            root.muteApp(appName);
        }

        function unmute(appName: string): void {
            root.unmuteApp(appName);
        }

        /// What the notification search would show, so the filter can be checked
        /// without a pointer.
        function search(query: string): string {
            return JSON.stringify(root.list.filter(n => root.matchesQuery(n, query)).map(n => n.appName));
        }

        /// The quiet state, whoever asked for it.
        function isDndEnabled(): bool {
            return root.quiet;
        }

        /// Claim or release a named reason to stay quiet. The lock screen's game is
        /// the caller that cannot touch the model directly.
        function setDndHold(reason: string, held: bool): void {
            root.setDndHold(reason, held);
        }

        function toggleDnd(): void {
            props.dnd = !props.dnd;
        }

        function enableDnd(): void {
            props.dnd = true;
        }

        function disableDnd(): void {
            props.dnd = false;
        }

        target: "notifs"
    }

    Component {
        id: notifComp

        NotifData {
            onClosedChanged: {
                root.openCount = closed ? Math.max(0, root.openCount - 1) : root.openCount + 1;
            }
            onPopupChanged: {
                root.popupCount = popup ? root.popupCount + 1 : Math.max(0, root.popupCount - 1);
                if (root.popupCount === 0)
                    root.activeTargetOutput = "";
            }
        }
    }
}
