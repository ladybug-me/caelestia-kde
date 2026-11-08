pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.bar
import qs.modules.nexus
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> branchItems: branchVariants.instances

    readonly property var activeBranchItem: {
        const found = branchItems.find(function(i) { return i.text === UpdateChecker.currentBranch; });
        return found || (branchItems.length > 0 ? branchItems[0] : null);
    }

    property string selectedVersionId: ""
    property string pendingBranch: ""
    property double nowMs: Date.now()
    property bool launchFailed: false
    property string backupError: ""

    property bool configuredTerminalAvailable: true
    property bool konsoleAvailable: false

    readonly property bool branchDataLoading: root.pendingBranch !== "" && UpdateChecker.checkingUpdates
    readonly property bool updaterActive: UpdateChecker.updaterPending || UpdateChecker.updaterRunning
    readonly property bool checkingOff: !UpdateChecker.checkingEnabled

    readonly property var selectedEntry: {
        for (let i = 0; i < root.timelineEntries.length; i++) {
            if (root.timelineEntries[i].id === root.selectedVersionId)
                return root.timelineEntries[i];
        }
        return null;
    }

    readonly property string selectedVersionState: root.selectedEntry ? root.selectedEntry.state : ""
    readonly property string selectedVersionLabel: root.selectedEntry ? root.selectedEntry.label : root.selectedVersionId
    readonly property bool selectionIsRevert: root.selectedVersionState === "past"
    readonly property bool selectionIsFuture: root.selectedVersionState === "available"
    readonly property bool selectionIsReinstall: root.selectedVersionState === "current"
    readonly property bool hasSelection: root.selectedVersionId !== "" && root.selectedEntry !== null

    readonly property string availableVersion: UpdateChecker.availableVersions.length > 0 ? UpdateChecker.availableVersions[0].replace(/^v/i, "") : ""

    readonly property var timelineEntries: {
        if (UpdateChecker.versionSummaryMode && UpdateChecker.availableVersions.length > 0) {
            const bodies = {};
            for (let c = 0; c < UpdateChecker.commits.length; c++) {
                const commit = UpdateChecker.commits[c];
                bodies[root.normalizeVersion(commit.subject)] = commit.details || "";
            }

            const versions = UpdateChecker.availableVersions;
            const current = UpdateChecker.currentVersion;
            const currentIdx = current === "unknown" ? -2 : versions.findIndex(v => root.normalizeVersion(v) === root.normalizeVersion(current));
            const result = [];
            for (let i = 0; i < versions.length; i++) {
                let state;
                if (currentIdx === -2) {
                    state = "past";
                } else if (currentIdx === -1) {
                    state = i === 0 ? "current" : "past";
                } else if (i < currentIdx) {
                    state = "available";
                } else if (i === currentIdx) {
                    state = "current";
                } else {
                    state = "past";
                }
                result.push({
                    id: versions[i],
                    label: versions[i].replace(/^v/i, ""),
                    state: state,
                    subject: "",
                    isRelease: true,
                    details: bodies[root.normalizeVersion(versions[i])] || "",
                    url: `https://github.com/ladybug-me/caelestia-kde/releases/tag/${versions[i]}`
                });
            }
            return result;
        }

        const commits = UpdateChecker.commits;
        const localHash = UpdateChecker.installedCommitHash;
        const localIdx = localHash !== "" ? commits.findIndex(c => c.fullHash === localHash || c.hash === localHash) : -1;
        const result = [];
        for (let i = 0; i < commits.length; i++) {
            const c = commits[i];
            let state;
            if (localHash === "") {
                state = i === 0 ? "current" : "past";
            } else if (localIdx === -1) {
                state = "available";
            } else if (i < localIdx) {
                state = "available";
            } else if (i === localIdx) {
                state = "current";
            } else {
                state = "past";
            }
            result.push({
                id: c.hash,
                label: c.hash,
                subject: c.subject || "",
                state: state,
                isMerge: !!c.isMerge,
                isRelease: false,
                author: c.author || "",
                date: c.date || "",
                details: ""
            });
        }
        return result;
    }

    readonly property string notesText: {
        const entry = root.selectedEntry;
        if (entry !== null && entry.isRelease)
            return root.formatNotes(entry.details);
        const latest = root.timelineEntries.find(e => e.state === "available" && e.isRelease);
        return latest ? root.formatNotes(latest.details) : "";
    }

    readonly property string releaseUrl: {
        const entry = root.selectedEntry;
        if (entry !== null && entry.isRelease)
            return entry.url;
        const latest = root.timelineEntries.find(e => e.state === "available" && e.isRelease);
        return latest ? latest.url : "";
    }

    readonly property list<string> terminalCommand: root.configuredTerminalAvailable ? GlobalConfig.general.apps.terminal : ["konsole"]
    readonly property bool terminalAvailable: root.configuredTerminalAvailable || root.konsoleAvailable

    readonly property string primaryActionText: {
        if (root.launchFailed)
            return qsTr("Copy command");
        if (root.updaterActive)
            return qsTr("Open terminal again");
        if (root.selectionIsRevert)
            return qsTr("Restore %1").arg(root.selectedVersionLabel);
        if (root.selectionIsReinstall)
            return qsTr("Reinstall %1").arg(root.selectedVersionLabel);
        if (root.selectionIsFuture)
            return qsTr("Update to %1").arg(root.selectedVersionLabel);
        if (UpdateChecker.hasUpdate) {
            if (UpdateChecker.versionSummaryMode && root.availableVersion !== "")
                return qsTr("Update to %1").arg(root.availableVersion);
            return qsTr("Update now");
        }
        if (UpdateChecker.checkFailed)
            return qsTr("Try again");
        if (root.checkingOff)
            return qsTr("Turn on");
        return "";
    }

    readonly property string primaryActionIcon: {
        if (root.launchFailed)
            return "content_copy";
        if (root.updaterActive)
            return "open_in_new";
        if (root.selectionIsRevert)
            return "history";
        if (root.selectionIsReinstall)
            return "replay";
        if (root.selectionIsFuture || UpdateChecker.hasUpdate)
            return "system_update_alt";
        if (UpdateChecker.checkFailed)
            return "refresh";
        if (root.checkingOff)
            return "sync";
        return "refresh";
    }

    readonly property string secondaryActionText: {
        if (root.updaterActive)
            return qsTr("Copy command");
        if (root.hasSelection)
            return qsTr("Clear selection");
        if (UpdateChecker.hasUpdate && !UpdateChecker.checkingUpdates)
            return qsTr("Check again");
        return "";
    }

    readonly property string selectionActionText: {
        if (!root.hasSelection)
            return "";
        if (root.selectionIsRevert)
            return qsTr("Restore %1").arg(root.selectedVersionLabel);
        if (root.selectionIsReinstall)
            return qsTr("Reinstall %1").arg(root.selectedVersionLabel);
        return qsTr("Update to %1").arg(root.selectedVersionLabel);
    }

    readonly property string statusIcon: {
        if (root.selectionIsRevert)
            return "history";
        if (root.selectionIsReinstall)
            return "replay";
        if (root.selectionIsFuture)
            return "system_update_alt";
        return UpdateChecker.statusIcon;
    }

    readonly property string statusTitle: {
        if (root.launchFailed)
            return qsTr("Couldn't open a terminal");
        if (root.selectionIsRevert)
            return qsTr("Restore %1?").arg(root.selectedVersionLabel);
        if (root.selectionIsReinstall)
            return qsTr("Reinstall %1?").arg(root.selectedVersionLabel);
        if (root.selectionIsFuture)
            return qsTr("Update to %1?").arg(root.selectedVersionLabel);
        return UpdateChecker.statusTitle;
    }

    readonly property string statusDetail: {
        if (root.launchFailed)
            return qsTr("Run %1 in a terminal instead").arg(UpdateChecker.updaterCommand(root.selectedVersionId));
        if (root.updaterActive) {
            if (UpdateChecker.updaterRunning)
                return qsTr("The shell restarts when it finishes");
            return qsTr("Running %1").arg(UpdateChecker.updaterCommand());
        }
        if (root.hasSelection) {
            const parts = [];
            if (UpdateChecker.currentVersion !== "unknown")
                parts.push(qsTr("From %1").arg(UpdateChecker.currentVersion));
            if (root.selectionIsRevert)
                parts.push(qsTr("older version"));
            parts.push(qsTr("settings are backed up"));
            parts.push(qsTr("the shell restarts"));
            return parts.join(" · ");
        }
        return UpdateChecker.statusDetailFor(root.nowMs);
    }

    readonly property bool statusHighlighted: root.hasSelection || UpdateChecker.hasUpdate || root.launchFailed || UpdateChecker.checkFailed

    function normalizeVersion(version): string {
        return (version || "").replace(/^v/i, "");
    }

    function formatNotes(body): string {
        if (!body || body === "")
            return "";
        const lines = body.split("\n");
        const out = [];
        for (let i = 0; i < lines.length && out.length < 12; i++) {
            let line = lines[i].trim();
            if (line === "" || line.startsWith("#"))
                continue;
            line = line.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1");
            line = line.replace(/^[*-]\s+/, "• ");
            out.push(line);
        }
        return out.join("\n");
    }

    function runCheck(): void {
        root.launchFailed = false;
        UpdateChecker.checkUpdates("", false, true);
    }

    function launchUpdater(): void {
        const version = root.selectedVersionId !== "" ? root.selectedVersionId : (root.updaterActive ? UpdateChecker.updaterVersion : "");
        const command = [UpdateChecker.currentBranch];
        if (version !== "")
            command.push(version);

        if (!root.terminalAvailable) {
            root.launchFailed = true;
            return;
        }

        root.launchFailed = false;
        root.selectedVersionId = "";

        const hold = 'caelestia-update "$@"; s=$?; printf "\\n[caelestia-update exited with status %s] Press Enter to close..." "$s"; read -r _';
        Launch.exec([...root.terminalCommand, "sh", "-c", hold, "sh", ...command]);
        UpdateChecker.markUpdaterLaunched(version);
    }

    function restoreVersion(): void {
        confirmDialog.open();
    }

    function runPrimaryAction(): void {
        if (root.launchFailed) {
            UpdateChecker.copyUpdaterCommand(root.selectedVersionId);
            return;
        }
        if (root.updaterActive) {
            root.launchUpdater();
            return;
        }
        if (root.hasSelection) {
            if (root.selectionIsRevert)
                root.restoreVersion();
            else
                root.launchUpdater();
            return;
        }
        if (UpdateChecker.hasUpdate) {
            root.launchUpdater();
            return;
        }
        if (UpdateChecker.checkFailed) {
            root.runCheck();
            return;
        }
        if (root.checkingOff) {
            GlobalConfig.general.checkUpdates = true;
            root.runCheck();
        }
    }

    function runSecondaryAction(): void {
        if (root.updaterActive) {
            UpdateChecker.copyUpdaterCommand(root.selectedVersionId);
            return;
        }
        if (root.hasSelection) {
            root.selectedVersionId = "";
            return;
        }
        root.runCheck();
    }

    function toggleSelection(entryId): void {
        root.selectedVersionId = root.selectedVersionId === entryId ? "" : entryId;
    }

    title: qsTr("Updates")

    headerActions: [
        IconTextButton {
            text: qsTr("Help")
            icon: "help"
            type: TextButton.Tonal
            onClicked: Qt.openUrlExternally("https://github.com/ladybug-me/caelestia-kde/blob/main/docs/TROUBLESHOOTING.md#10-update-issues")
        }
    ]

    Item {
        visible: false

        Variants {
            id: branchVariants

            model: UpdateChecker.availableBranches

            MenuItem {
                required property string modelData

                text: modelData
                icon: "call_split"
            }
        }

        Connections {
            function onCommitsChanged() { root.selectedVersionId = ""; }

            function onVersionSummaryModeChanged() { root.selectedVersionId = ""; }

            function onAvailableVersionsChanged() { root.selectedVersionId = ""; }

            function onCurrentBranchChanged() { root.selectedVersionId = ""; }

            function onCurrentVersionChanged() { root.selectedVersionId = ""; }

            function onInstalledCommitHashChanged() { root.selectedVersionId = ""; }

            function onCheckingUpdatesChanged() {
                if (!UpdateChecker.checkingUpdates)
                    root.pendingBranch = "";
            }

            target: UpdateChecker
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            visible: !root.branchDataLoading
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: statusCol.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: statusCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Tokens.padding.largeIncreased
                }

                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    fontStyle: Tokens.font.icon.extraLarge
                    text: root.statusIcon
                    color: root.statusHighlighted ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    font: Tokens.font.title.medium
                    color: root.statusHighlighted ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.statusTitle
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.statusDetail
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                IconTextButton {
                    id: primaryButton

                    readonly property bool busy: UpdateChecker.checkingUpdates && root.primaryActionText === ""

                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    text: root.primaryActionText !== "" ? root.primaryActionText : (UpdateChecker.checkingUpdates ? qsTr("Checking…") : qsTr("Check again"))
                    type: TextButton.Filled
                    font: Tokens.font.body.medium
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.medium
                    icon: root.primaryActionText !== "" ? root.primaryActionIcon : "refresh"
                    disabled: busy
                    onClicked: {
                        if (root.primaryActionText !== "")
                            root.runPrimaryAction();
                        else
                            root.runCheck();
                    }

                    RotationAnimation {
                        target: primaryButton.iconLabel
                        property: "rotation"
                        running: primaryButton.busy && Tokens.anim.enabled
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }

                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.secondaryActionText !== ""
                    text: root.secondaryActionText
                    type: TextButton.Text
                    font: Tokens.font.body.medium
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.small
                    onClicked: root.runSecondaryAction()
                }

                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.updaterActive && !root.launchFailed
                    text: qsTr("Dismiss")
                    type: TextButton.Text
                    font: Tokens.font.label.medium
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.extraSmall
                    onClicked: UpdateChecker.dismissUpdater()
                }
            }
        }

        ConnectedRect {
            visible: root.branchDataLoading
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: loadingCol.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: loadingCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Tokens.padding.largeIncreased
                }

                spacing: Tokens.spacing.small

                LoadingIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    implicitSize: Math.round(Tokens.font.icon.extraLarge.pointSize * 1.6)
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                    text: qsTr("Switching to %1…").arg(root.pendingBranch)
                }
            }
        }

        SectionHeader {
            visible: !root.branchDataLoading && root.notesText !== ""
            text: qsTr("Release notes")
        }

        ConnectedRect {
            visible: !root.branchDataLoading && root.notesText !== ""
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: notesCol.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: notesCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Tokens.padding.largeIncreased
                }

                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: root.notesText
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.small
                    wrapMode: Text.Wrap
                }

                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.releaseUrl !== ""
                    text: qsTr("Full release notes")
                    type: TextButton.Text
                    font: Tokens.font.body.small
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.small
                    onClicked: Qt.openUrlExternally(root.releaseUrl)
                }
            }
        }

        SectionHeader {
            visible: !root.branchDataLoading && root.timelineEntries.length > 0
            text: UpdateChecker.versionSummaryMode ? qsTr("Version history") : qsTr("Commit history")
        }

        ConnectedRect {
            visible: !root.branchDataLoading && root.timelineEntries.length > 0
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: timeline.implicitHeight + Tokens.padding.medium * 2

            UpdateTimeline {
                id: timeline

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Tokens.padding.medium
                }

                entries: root.timelineEntries
                selectedId: root.selectedVersionId
                selectActionLabel: root.selectionActionText
                onEntryClicked: (entryId, entryState) => root.toggleSelection(entryId)
                onInstallRequested: {
                    if (root.selectionIsRevert)
                        root.restoreVersion();
                    else
                        root.launchUpdater();
                }
                onSelectionCleared: root.selectedVersionId = ""
            }
        }

        ConnectedRect {
            visible: !root.branchDataLoading && root.timelineEntries.length === 0
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: emptyCol.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: emptyCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Tokens.padding.largeIncreased
                }

                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    fontStyle: Tokens.font.icon.large
                    text: "history"
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("No history yet")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("The first successful check fills this in.")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                }

                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    text: UpdateChecker.checkingUpdates ? qsTr("Checking…") : qsTr("Check now")
                    type: TextButton.Tonal
                    font: Tokens.font.body.medium
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.medium
                    disabled: UpdateChecker.checkingUpdates
                    onClicked: root.runCheck()
                }
            }
        }

        TextButton {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.branchDataLoading && !UpdateChecker.versionSummaryMode && UpdateChecker.hasMoreCommits
            text: UpdateChecker.loadingMoreCommits ? qsTr("Loading…") : qsTr("Load older commits")
            type: TextButton.Tonal
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.large
            verticalPadding: Tokens.padding.medium
            disabled: UpdateChecker.loadingMoreCommits
            onClicked: UpdateChecker.loadMoreCommits()
        }

        SectionHeader {
            visible: !root.branchDataLoading
            text: qsTr("Update settings")
        }

        SelectRow {
            first: true
            enabled: !root.branchDataLoading
            label: qsTr("Update channel")
            subtext: UpdateChecker.currentBranch === "main" ? qsTr("Stable releases") : qsTr("Development builds — may be unstable")
            menuItems: root.branchItems
            active: root.activeBranchItem
            fallbackText: UpdateChecker.currentBranch
            fallbackIcon: "call_split"
            onSelected: function(item) {
                root.selectedVersionId = "";
                root.pendingBranch = item.text !== UpdateChecker.currentBranch ? item.text : "";
                UpdateChecker.checkUpdates(item.text, undefined, true);
            }
        }

        ToggleRow {
            last: true
            visible: !root.branchDataLoading
            text: qsTr("Check for updates automatically")
            subtext: qsTr("Every 30 minutes, and once when the shell starts")
            reset: ({ node: GlobalConfig.general, setting: "checkUpdates" })
            checked: GlobalConfig.general.checkUpdates
            onToggled: GlobalConfig.general.checkUpdates = checked
        }

        SectionHeader {
            visible: !root.branchDataLoading
            text: qsTr("Maintenance")
        }

        NavRow {
            first: true
            last: true
            visible: !root.branchDataLoading
            icon: "folder"
            label: qsTr("Open backup folder")
            status: root.backupError !== "" ? root.backupError : qsTr("View your previously backed-up configuration files")
            onClicked: {
                root.backupError = "";
                backupFolderProcess.running = true;
            }
        }

        Timer {
            interval: 15000
            repeat: true
            running: true
            onTriggered: root.nowMs = Date.now()
        }

        Process {
            id: terminalCheck

            command: ["bash", "-c", "command -v \"$1\" >/dev/null 2>&1", "--", GlobalConfig.general.apps.terminal[0] || ""]
            running: true
            onExited: code => root.configuredTerminalAvailable = code === 0
        }

        Process {
            id: konsoleCheck

            command: ["bash", "-c", "command -v konsole >/dev/null 2>&1"]
            running: true
            onExited: code => root.konsoleAvailable = code === 0
        }

        Process {
            id: backupFolderProcess

            command: ["sh", "-c",
                'dir="$1"; shift; mkdir -p "$dir" && exec "$@" "$dir"',
                "--",
                Paths.absolutePath("~/.config/caelestia-update/backups")
            ].concat(GlobalConfig.general.apps.explorer)
            onExited: code => {
                if (code !== 0)
                    root.backupError = qsTr("Couldn't open the folder — it is at ~/.config/caelestia-update/backups");
            }
        }

        UpdateConfirmDialog {
            id: confirmDialog

            toVersion: root.selectedVersionLabel
            fromVersion: UpdateChecker.currentVersion !== "unknown" ? UpdateChecker.currentVersion : ""
            onConfirmed: root.launchUpdater()
        }
    }
}
