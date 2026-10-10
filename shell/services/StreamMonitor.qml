pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Caelestia
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property bool sharing: false
    property bool prevDnd: false
    property bool autoDnd: false
    property int seedHits: 0
    property int seedMisses: 0

    function isSharingNode(node): bool {
        if (!node)
            return false;
        const props = node.properties ?? {};
        const mediaClass = props["media.class"] || "";
        const nodeName = props["node.name"] || node.name || "";
        if (mediaClass === "Stream/Input/Video") {
            const mediaName = props["media.name"] || "";
            if (nodeName === "quickshell" || nodeName === "caelestia-shell" || mediaName.indexOf("plasma-screencast-") === 0)
                return false;
            return true;
        }
        if (mediaClass === "Video/Source") {
            const mediaRole = props["media.role"] || "";
            if (mediaRole === "Camera" || nodeName.indexOf("v4l2_input") === 0)
                return false;
            return true;
        }
        return false;
    }

    function rescan(): void {
        let found = false;
        for (const node of Pipewire.nodes.values) {
            if (root.isSharingNode(node)) {
                found = true;
                break;
            }
        }
        if (found || Recorder.running) {
            root.seedMisses = 0;
            if (++root.seedHits >= 2 && !root.sharing)
                root.sharing = true;
        } else {
            root.seedHits = 0;
            if (++root.seedMisses >= 3 && root.sharing)
                root.sharing = false;
        }
    }

    onSharingChanged: {
        if (!Config.utilities.toasts.dndWhileStreaming)
            return;
        if (root.sharing && !Notifs.dnd) {
            root.prevDnd = Notifs.dnd;
            root.autoDnd = true;
            Notifs.dnd = true;
        } else if (!root.sharing && root.autoDnd) {
            root.autoDnd = false;
            Notifs.dnd = root.prevDnd;
        }
    }

    Component.onCompleted: root.rescan()

    Connections {
        function onDndWhileStreamingChanged(): void {
            if (!Config.utilities.toasts.dndWhileStreaming && root.autoDnd) {
                root.autoDnd = false;
                Notifs.dnd = root.prevDnd;
            } else if (Config.utilities.toasts.dndWhileStreaming && root.sharing && !Notifs.dnd) {
                root.prevDnd = Notifs.dnd;
                root.autoDnd = true;
                Notifs.dnd = true;
            }
        }

        target: Config.utilities.toasts
    }

    Connections {
        function onDndChanged(): void {
            if (root.autoDnd && !Notifs.dnd)
                root.autoDnd = false;
        }

        target: Notifs
    }

    Connections {
        function onObjectInsertedPost(): void {
            root.rescan();
        }
        function onObjectRemovedPost(): void {
            root.rescan();
        }
        function onValuesChanged(): void {
            root.rescan();
        }

        target: Pipewire.nodes
    }

    Connections {
        function onRunningChanged(): void {
            root.rescan();
        }

        target: Recorder
    }
}
