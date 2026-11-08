pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// One description of the update state for every surface that reports it: the
// page, the bar popout and the bar indicator all render `describe()` rather than
// deciding for themselves what to say. A surface that knows more (the page knows
// about a selected version, and about a terminal it failed to open) passes that in
// and gets the same object back.
Singleton {
    id: root

    property double now: Date.now()

    readonly property var current: root.describe(null, false)

    function action(key, label, icon): var {
        return {
            key: key,
            label: label,
            icon: icon
        };
    }

    function card(icon, title, detail, primary, secondary, extra): var {
        const result = {
            icon: icon,
            title: title,
            detail: detail,
            primary: primary === undefined ? null : primary,
            secondary: secondary === undefined ? null : secondary,
            dismissible: false,
            highlight: false
        };
        if (extra !== undefined) {
            for (const key in extra)
                result[key] = extra[key];
        }
        return result;
    }

    function formatDuration(ms: real): string {
        const seconds = Math.max(0, Math.floor(ms / 1000));
        if (seconds < 60)
            return qsTr("less than a minute");
        const minutes = Math.floor(seconds / 60);
        if (minutes < 60)
            return qsTr("%1 min").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return qsTr("%1 h").arg(hours);
        return qsTr("%1 d").arg(Math.floor(hours / 24));
    }

    function versionText(): string {
        const version = UpdateChecker.currentVersion;
        return version === "unknown" || version === "" ? "" : version;
    }

    // When the check itself last worked, which is what a failure has to report:
    // the last attempt is useless once it failed.
    function checkTiming(): string {
        if (UpdateChecker.checkingUpdates)
            return qsTr("checking now");
        if (!UpdateChecker.everChecked)
            return qsTr("not checked yet");
        const parts = [qsTr("checked %1 ago").arg(root.formatDuration(root.now - UpdateChecker.lastCheckSuccessMs))];
        if (UpdateChecker.checkingEnabled && UpdateChecker.handoff === UpdateChecker.Handoff.None)
            parts.push(qsTr("next in %1").arg(root.formatDuration(UpdateChecker.lastCheckSuccessMs + UpdateChecker.checkIntervalMs - root.now)));
        return parts.join(" · ");
    }

    function baseDetail(): string {
        const parts = [];
        const version = root.versionText();
        if (version !== "")
            parts.push(version);
        if (UpdateChecker.checkFailed) {
            parts.push(UpdateChecker.everChecked ? qsTr("last success %1 ago").arg(root.formatDuration(root.now - UpdateChecker.lastCheckSuccessMs)) : qsTr("never checked successfully"));
            parts.push(UpdateChecker.checkError);
            return parts.join(" · ");
        }
        parts.push(root.checkTiming());
        return parts.join(" · ");
    }

    function latestVersion(): string {
        const versions = UpdateChecker.availableVersions;
        return versions.length > 0 ? versions[0].replace(/^v/i, "") : "";
    }

    function selectionTitle(state, label): string {
        if (state === "past")
            return qsTr("Restore %1?").arg(label);
        if (state === "current")
            return qsTr("Reinstall %1?").arg(label);
        return qsTr("Update to %1?").arg(label);
    }

    function selectionAction(state, label): var {
        if (state === "past")
            return root.action("restore", qsTr("Restore %1").arg(label), "history");
        if (state === "current")
            return root.action("reinstall", qsTr("Reinstall %1").arg(label), "replay");
        return root.action("install", qsTr("Update to %1").arg(label), "system_update_alt");
    }

    function selectionDetail(state): string {
        const parts = [];
        const version = root.versionText();
        if (version !== "")
            parts.push(qsTr("From %1").arg(version));
        if (state === "past")
            parts.push(qsTr("older version"));
        parts.push(qsTr("settings are backed up"));
        parts.push(qsTr("the shell restarts"));
        return parts.join(" · ");
    }

    function selectionIcon(state): string {
        if (state === "past")
            return "history";
        if (state === "current")
            return "replay";
        return "system_update_alt";
    }

    function describe(selection, launchFailed): var {
        const command = UpdateChecker.updaterArgs().join(" ");

        if (launchFailed) {
            return root.card("error", qsTr("Couldn't open a terminal"), qsTr("Run %1 in a terminal instead").arg(command), root.action("copy", qsTr("Copy command"), "content_copy"), null, {
                highlight: true
            });
        }

        if (UpdateChecker.handoff === UpdateChecker.Handoff.Running) {
            return root.card("terminal", qsTr("Updating in the terminal"), qsTr("The shell restarts when it finishes"), root.action("reopen", qsTr("Open terminal again"), "open_in_new"), root.action("copy", qsTr("Copy command"), "content_copy"), {
                dismissible: true,
                highlight: true
            });
        }

        if (UpdateChecker.handoff === UpdateChecker.Handoff.Pending) {
            return root.card("terminal", qsTr("Opening the terminal…"), qsTr("Running %1").arg(command), root.action("reopen", qsTr("Open terminal again"), "open_in_new"), root.action("copy", qsTr("Copy command"), "content_copy"), {
                dismissible: true,
                highlight: true
            });
        }

        if (selection !== null && selection !== undefined) {
            const clear = root.action("clear", qsTr("Clear selection"), "close");
            return root.card(root.selectionIcon(selection.state), root.selectionTitle(selection.state, selection.label), root.selectionDetail(selection.state), root.selectionAction(selection.state, selection.label), clear, {
                highlight: true
            });
        }

        if (UpdateChecker.checkingUpdates) {
            return root.card("sync", qsTr("Checking for updates…"), root.baseDetail(), null, null);
        }

        if (UpdateChecker.checkFailed) {
            return root.card("cloud_off", qsTr("Couldn't check for updates"), root.baseDetail(), root.action("check", qsTr("Try again"), "refresh"), null, {
                highlight: true
            });
        }

        if (UpdateChecker.hasUpdate) {
            const latest = root.latestVersion();
            const title = UpdateChecker.versionSummaryMode
                ? (latest !== "" ? qsTr("Version %1 is available").arg(latest) : qsTr("An update is available"))
                : qsTr("%1 new commits on %2").arg(UpdateChecker.pendingCount).arg(UpdateChecker.currentBranch);
            const primary = root.action("install", latest !== "" && UpdateChecker.versionSummaryMode ? qsTr("Update to %1").arg(latest) : qsTr("Update now"), "system_update_alt");
            return root.card("update", title, root.baseDetail(), primary, root.action("check", qsTr("Check again"), "refresh"), {
                highlight: true
            });
        }

        if (!UpdateChecker.checkingEnabled) {
            return root.card("sync_disabled", qsTr("Update checking is off"), root.baseDetail(), root.action("turnOn", qsTr("Turn on"), "sync"), null);
        }

        if (root.versionText() === "") {
            return root.card("help", qsTr("Installed version unknown"), root.baseDetail(), root.action("check", qsTr("Check again"), "refresh"), null);
        }

        return root.card("check_circle", qsTr("You're up to date"), root.baseDetail(), null, root.action("check", qsTr("Check again"), "refresh"));
    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        onTriggered: root.now = Date.now()
    }
}
