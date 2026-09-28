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
    property int openCount: 0
    property int popupCount: 0

    readonly property int notifCap: Math.max(1, GlobalConfig.notifs.maxNotifs)

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
        return JSON.stringify(root.notClosed().map(n => ({
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

            root.openCount++;
            if (showPopup)
                root.popupCount++;

            const next = [comp, ...root.list];
            const cap = root.notifCap;
            if (next.length > cap) {
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
            const cap = root.notifCap;
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
