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

Singleton {
    id: root

    property list<NotifData> list: []
    // Incremental counters — updated by each NotifData's change handlers below.
    // This avoids the full-list filter() that fires on every state change.
    property int openCount: 0
    property int popupCount: 0

    property alias dnd: props.dnd
    property string lastSavedState: ""

    property string activeTargetOutput: ""
    property bool loaded

    function getCursorOutputName(): string {
        const monitor = Kwin.monitors[Kwin.cursorOutputName()] || Kwin.focusedMonitor;
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

    function shouldShowPopup(): bool {
        if (props.dnd || [...Visibilities.screens.values()].some(v => v.sidebar))
            return false;
        if (GlobalConfig.notifs.fullscreen === "off") {
            if (GlobalConfig.notifs.monitor === "focused") {
                const targetName = root.activeTargetOutput || root.getTargetOutput();
                if (targetName === "" || Kwin.hasFullscreenOn(targetName))
                    return false;
            } else {
                const scrList = Screens.screens || [];
                if (scrList.length > 0 && scrList.every(s => Kwin.hasFullscreenOn(s.name)))
                    return false;
                if (scrList.length === 0 && hasFullscreen())
                    return false;
            }
        }
        return true;
    }

    function shouldPlaySound(notif: Notification): bool {
        if (props.dnd)
            return false;
        if (notif.appName === "caelestia-cli" || GlobalConfig.audio.sounds.disabledNotifApps.includes(notif.appName))
            return false;
        if (GlobalConfig.notifs.fullscreen === "off") {
            if (GlobalConfig.notifs.monitor === "focused") {
                const targetName = root.activeTargetOutput || root.getTargetOutput();
                if (targetName === "" || Kwin.hasFullscreenOn(targetName))
                    return false;
            } else {
                const scrList = Screens.screens || [];
                if (scrList.length > 0 && scrList.every(s => Kwin.hasFullscreenOn(s.name)))
                    return false;
                if (scrList.length === 0 && hasFullscreen())
                    return false;
            }
        }
        return true;
    }

    function clear(): void {
        // Detach everything in one assignment before closing any of it.
        //
        // Closing a notification rebuilds this list (filter + reassign), and the
        // reassignment re-runs every derived binding: the unread counters in the
        // bar and the per-app filters in both notification docks — each of them a
        // full pass over the list. Closing one at a time therefore costs O(n) work
        // per notification plus a full view rebuild, so with a couple of thousand
        // stored it hangs the shell outright.
        //
        // Emptying the list first drops those dependencies, so the views update
        // once and each close() below is just a dismiss and a destroy.
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

    function serializeState(): string {
        return JSON.stringify(root.notClosed().map(n => ({  // notClosed() called once, not a binding
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
                    })));
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

        // Back off when the list is large to reduce serialisation pressure.
        // At 500 items this is ~8 s; at 0 it is 3 s.
        interval: Math.min(10000, 3000 + root.list.length * 10)
        onTriggered: {
            const serialized = root.serializeState();
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

        onNotification: notif => {
            notif.tracked = true;

            root.activeTargetOutput = root.getTargetOutput();

            const showPopup = root.shouldShowPopup();
            const comp = notifComp.createObject(root, {
                popup: showPopup,
                notification: notif
            });

            // onClosedChanged / onPopupChanged only fire on *transitions*, not on
            // initial construction. A fresh notification always starts closed=false,
            // so we must increment the counters explicitly here.
            root.openCount++;
            if (showPopup)
                root.popupCount++;

            const next = [comp, ...root.list];
            const cap = GlobalConfig.notifs.maxNotifs;
            if (next.length > cap) {
                // Evict oldest items (tail) before assigning — one list update total.
                const evicted = next.splice(cap);
                for (const old of evicted) old.close();
            }
            root.list = next;

            if (root.shouldPlaySound(notif))
                Audio.playNotification();
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/notifs.json`
        onLoaded: {
            const data = JSON.parse(text());
            const cap = GlobalConfig.notifs.maxNotifs;
            for (const notif of data.slice(0, cap))
                root.list.push(notifComp.createObject(root, notif));
            root.list.sort((a, b) => b.time - a.time);
            root.openCount = root.list.filter(n => !n.closed).length;
            root.popupCount = root.list.filter(n => n.popup).length;
            root.lastSavedState = root.serializeState();
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
        function clear(): void {
            root.clear();
        }

        function isDndEnabled(): bool {
            return props.dnd;
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
                // Maintain openCount incrementally instead of re-filtering the list.
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
