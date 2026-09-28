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
import qs.modules.nexus
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> branchItems: branchVariants.instances

    readonly property var activeBranchItem: {
        const found = branchItems.find(function(i) { return i.text === UpdateChecker.currentBranch; });
        return found || (branchItems.length > 0 ? branchItems[0] : null);
    }

    readonly property bool updateRunning: UpdateChecker.updateRunning

    readonly property real updateProgress: UpdateChecker.updateProgress

    readonly property string updateStatus: UpdateChecker.updateStatus

    readonly property string updateLogs: UpdateChecker.updateLogs

    property string selectedVersionId: ""

    property string pendingBranch: ""

    property bool installOptionsExpanded: false

    readonly property bool branchDataLoading: root.pendingBranch !== "" && UpdateChecker.checkingUpdates

    readonly property int updatesPageIdx: {
        const idx = PageRegistry.indexForKey("updates");
        if (idx >= 0) return idx;
        return PageRegistry.pages.length > 0 ? Math.min(Math.max(nState.currentPageIdx, 0), PageRegistry.pages.length - 1) : 0;
    }

    readonly property var selectedEntry: {
        for (let i = 0; i < root.timelineEntries.length; i++) {
            if (root.timelineEntries[i].id === root.selectedVersionId)
                return root.timelineEntries[i];
        }
        return null;
    }

    readonly property bool timelineSelectionEnabled: true

    readonly property string selectedVersionState: root.selectedEntry ? root.selectedEntry.state : ""

    readonly property bool selectionIsRevert: root.timelineSelectionEnabled && root.selectedVersionState === "past"

    readonly property bool selectionIsFuture: root.timelineSelectionEnabled && root.selectedVersionState === "available"

    readonly property bool selectionIsReinstall: root.timelineSelectionEnabled && root.selectedVersionState === "current"

    readonly property bool primaryActionVisible: {
        if (root.updateRunning) return false;
        if (root.updateProgress === 1.0) return true;
        if (root.selectionIsRevert) return true;
        if (root.selectionIsReinstall) return true;
        if (root.selectionIsFuture && root.selectedVersionId !== "") return true;
        return UpdateChecker.hasUpdate;
    }

    readonly property var timelineEntries: {
        if (UpdateChecker.versionSummaryMode && UpdateChecker.availableVersions.length > 0) {
            const versions = UpdateChecker.availableVersions;
            const current = UpdateChecker.currentVersion;
            const currentIdx = current === "unknown"
                ? -2
                : versions.findIndex(v => v === current || v.replace(/^v/i, "") === current.replace(/^v/i, ""));
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
                result.push({ id: versions[i], label: versions[i], state: state, subject: "", isRelease: true });
            }
            return result;
        } else {
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
                    date: c.date || ""
                });
            }
            return result.filter(e => !e.isMerge || e.state === "current");
        }
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
                    text: {
                        if (root.updateProgress === 1.0) return "done_all";
                        if (root.updateRunning) return "sync";
                        if (root.selectionIsRevert) return "history";
                        if (root.selectionIsReinstall) return "replay";
                        if (UpdateChecker.currentVersion === "unknown" && !UpdateChecker.hasUpdate) return "help";
                        return UpdateChecker.hasUpdate ? "update" : "check_circle";
                    }
                    color: (UpdateChecker.hasUpdate || root.updateRunning || root.updateProgress === 1.0 || root.selectedVersionId !== "")
                        ? Colours.palette.m3primary
                        : Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    font: Tokens.font.title.medium
                    color: (UpdateChecker.hasUpdate || root.updateRunning || root.updateProgress === 1.0 || root.selectedVersionId !== "")
                        ? Colours.palette.m3onSurface
                        : Colours.palette.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: {
                        if (root.updateProgress === 1.0) return qsTr("Update complete - log out to apply");
                        if (root.updateRunning) return root.updateStatus || qsTr("Updating…");
                        if (root.selectionIsRevert) return qsTr("Restore to %1?").arg(root.selectedVersionId);
                        if (root.selectionIsReinstall) return qsTr("Reinstall %1?").arg(root.selectedVersionId);
                        if (root.selectionIsFuture && root.selectedVersionId !== "")
                            return qsTr("Install %1?").arg(root.selectedVersionId);
                        if (UpdateChecker.hasUpdate) {
                            return UpdateChecker.versionSummaryMode
                                ? qsTr("New version available on %1").arg(UpdateChecker.currentBranch)
                                : qsTr("%1 new commits on %2").arg(UpdateChecker.pendingCount).arg(UpdateChecker.currentBranch);
                        }
                        if (UpdateChecker.currentVersion === "unknown")
                            return qsTr("Installed version unknown");
                        return qsTr("You're up to date");
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: UpdateChecker.currentVersion !== "unknown" && !root.updateRunning && root.updateProgress !== 1.0 && root.selectedVersionId === ""
                    text: UpdateChecker.versionSummaryMode
                        ? qsTr("Installed: %1").arg(UpdateChecker.currentVersion)
                        : qsTr("Channel: %1").arg(UpdateChecker.currentBranch)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.extraSmall
                    visible: root.updateRunning
                    value: root.updateProgress
                    indeterminate: root.updateProgress === 0.0 && root.updateRunning
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    spacing: Tokens.spacing.small

                    IconTextButton {
                        Layout.fillWidth: true
                        visible: root.primaryActionVisible
                        text: {
                            if (root.updateProgress === 1.0) return qsTr("Log Out");
                            if (root.selectionIsRevert) return qsTr("Restore");
                            if (root.selectionIsReinstall) return qsTr("Reinstall");
                            if (root.selectionIsFuture && root.selectedVersionId !== "")
                                return qsTr("Install %1").arg(root.selectedVersionId);
                            return qsTr("Install Update");
                        }
                        type: TextButton.Filled
                        font: Tokens.font.body.medium
                        horizontalPadding: Tokens.padding.large
                        verticalPadding: Tokens.padding.medium
                        icon: {
                            if (root.updateProgress === 1.0) return "logout";
                            if (root.selectionIsRevert) return "history";
                            if (root.selectionIsReinstall) return "replay";
                            return "system_update_alt";
                        }
                        onClicked: {
                            if (root.updateProgress === 1.0) {
                                logoutProcess.running = true;
                            } else {
                                const target = root.selectedVersionId;
                                root.selectedVersionId = "";
                                if (!nState.isWindow) {
                                    WindowFactory.create(null, {
                                        initialPageIdx: root.updatesPageIdx
                                    });
                                    nState.close();
                                    Qt.callLater(() => UpdateChecker.startUpdate(target));
                                    return;
                                }
                                UpdateChecker.startUpdate(target);
                            }
                        }
                    }

                    IconTextButton {
                        id: secondaryActionButton

                        readonly property bool isChecking: UpdateChecker.checkingUpdates && !root.updateRunning && root.selectedVersionId === ""

                        Layout.fillWidth: !root.primaryActionVisible
                        visible: root.updateProgress !== 1.0
                        disabled: isChecking
                        text: {
                            if (root.updateRunning) return qsTr("Stop");
                            if (root.selectedVersionId !== "") return qsTr("Cancel");
                            if (isChecking) return qsTr("Checking…");
                            return qsTr("Check");
                        }
                        type: TextButton.Tonal
                        font: Tokens.font.body.medium
                        horizontalPadding: Tokens.padding.large
                        verticalPadding: Tokens.padding.medium
                        icon: root.updateRunning ? "stop" : (root.selectedVersionId !== "" ? "close" : "refresh")
                        onClicked: {
                            if (root.updateRunning) {
                                UpdateChecker.stopUpdate();
                            } else if (root.selectedVersionId !== "") {
                                root.selectedVersionId = "";
                            } else {
                                UpdateChecker.checkUpdates();
                            }
                        }

                        RotationAnimation {
                            target: secondaryActionButton.iconLabel
                            property: "rotation"
                            running: secondaryActionButton.isChecking
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                        }
                    }
                }
            }
        }

        SectionHeader { text: qsTr("General") }

        SelectRow {
            first: true
            enabled: !root.branchDataLoading
            label: qsTr("Update channel")
            subtext: UpdateChecker.currentBranch === "main"
                ? qsTr("Stable releases")
                : qsTr("Development builds - may be unstable")
            menuItems: root.branchItems
            active: root.activeBranchItem
            fallbackText: UpdateChecker.currentBranch
            fallbackIcon: "call_split"
            onSelected: function(item) {
                root.selectedVersionId = "";
                root.pendingBranch = item.text !== UpdateChecker.currentBranch ? item.text : "";
                UpdateChecker.checkUpdates(item.text);
            }
        }

        ToggleRow {
            visible: !root.branchDataLoading
            text: qsTr("Show Update Indicator")
            subtext: qsTr("Show a notification icon in the taskbar when updates are available")
            checked: {
                const entries = GlobalConfig.bar.entries;
                for (let i = 0; i < entries.length; i++) {
                    if (entries[i].id === "updateIndicator") return entries[i].enabled;
                }
                return false;
            }
            onToggled: {
                let entries = GlobalConfig.bar.entries;
                let found = false;
                for (let i = 0; i < entries.length; i++) {
                    if (entries[i].id === "updateIndicator") {
                        let entry = Object.assign({}, entries[i]);
                        entry.enabled = checked;
                        entries[i] = entry;
                        found = true;
                        break;
                    }
                }
                if (!found && checked) {
                    let insertIdx = entries.length;
                    for (let i = 0; i < entries.length; i++) {
                        if (entries[i].id === "github" || entries[i].id === "clock") {
                            insertIdx = i;
                            break;
                        } else if (entries[i].id === "tray") {
                            insertIdx = i + 1;
                        }
                    }
                    entries.splice(insertIdx, 0, { id: "updateIndicator", enabled: true, zone: "right" });
                }
                GlobalConfig.bar.entries = entries;
            }
        }

        ConnectedRect {
            visible: !root.branchDataLoading
            last: !root.installOptionsExpanded
            Layout.fillWidth: true
            implicitHeight: installHeaderRow.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                onClicked: root.installOptionsExpanded = !root.installOptionsExpanded
            }

            RowLayout {
                id: installHeaderRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "tune"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Customize Installation")
                    font: Tokens.font.body.small
                }

                MaterialIcon {
                    text: root.installOptionsExpanded ? "expand_less" : "expand_more"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }
            }
        }

        NavRow {
            visible: !root.branchDataLoading && root.installOptionsExpanded
            icon: "folder"
            label: qsTr("Open Backup Folder")
            status: qsTr("View your previously backed-up configuration files")
            onClicked: {
                backupFolderProcess.running = true;
            }
        }

        ToggleRow {
            visible: !root.branchDataLoading && root.installOptionsExpanded
            text: qsTr("Deploy Configurations")
            subtext: qsTr("Update your custom dotfiles in ~/.config")
            checked: UpdateChecker.deployConfigs
            onToggled: UpdateChecker.deployConfigs = checked
        }

        ToggleRow {
            visible: !root.branchDataLoading && root.installOptionsExpanded
            last: true
            text: qsTr("Build Shell UI")
            subtext: qsTr("Compile and install Quickshell UI updates")
            checked: UpdateChecker.buildShell
            onToggled: UpdateChecker.buildShell = checked
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
            visible: !root.branchDataLoading
            text: UpdateChecker.versionSummaryMode ? qsTr("Version History") : qsTr("Commit History")
        }

        ConnectedRect {
            id: timelineCard

            readonly property real maxListHeight: 6 * timeline.rowHeight

            visible: !root.branchDataLoading
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: Math.min(timeline.implicitHeight, maxListHeight) + Tokens.padding.medium * 2

            Flickable {
                id: timelineFlickable
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Tokens.padding.medium
                }

                height: Math.min(timeline.implicitHeight, timelineCard.maxListHeight)
                contentWidth: width
                contentHeight: timeline.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                ScrollBar.vertical: StyledScrollBar {
                    flickable: timelineFlickable
                }

                UpdateTimeline {
                    id: timeline

                    width: parent.width
                    entries: root.timelineEntries
                    selectedId: root.timelineSelectionEnabled ? root.selectedVersionId : ""
                    onEntryClicked: function(entryId, entryState) {
                        if (root.updateRunning || !root.timelineSelectionEnabled) return;
                        root.selectedVersionId = (root.selectedVersionId === entryId) ? "" : entryId;
                        UpdateChecker.targetVersion = "";
                    }
                }
            }
        }

        TextButton {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.branchDataLoading
                && !UpdateChecker.versionSummaryMode
                && UpdateChecker.hasMoreCommits
            text: UpdateChecker.loadingMoreCommits ? qsTr("Loading…") : qsTr("Load 10 More")
            type: TextButton.Tonal
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.large
            verticalPadding: Tokens.padding.medium
            disabled: UpdateChecker.loadingMoreCommits
            onClicked: UpdateChecker.loadMoreCommits()
        }

        SectionHeader {
            visible: !root.branchDataLoading && (root.updateRunning || root.updateLogs !== "")
            text: qsTr("Update Log")
        }

        ConnectedRect {
            first: true
            last: true
            Layout.fillWidth: true
            visible: !root.branchDataLoading && (root.updateRunning || root.updateLogs !== "")
            implicitHeight: logContent.implicitHeight + Tokens.padding.medium * 2

            ColumnLayout {
                id: logContent
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Tokens.padding.medium
                }

                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.fillWidth: true
                        text: root.updateStatus
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.medium
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    IconButton {
                        icon: UpdateChecker.logsExpanded ? "expand_less" : "expand_more"
                        onClicked: UpdateChecker.logsExpanded = !UpdateChecker.logsExpanded
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 240
                    visible: UpdateChecker.logsExpanded && (root.updateLogs !== "" || root.updateRunning)
                    color: Colours.tPalette.m3surfaceContainerLowest
                    radius: Tokens.rounding.small
                    clip: true

                    Flickable {
                        id: logFlickable

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        contentHeight: logText.implicitHeight
                        contentWidth: width
                        flickableDirection: Flickable.VerticalFlick
                        onContentHeightChanged: {
                            if (contentHeight > height) contentY = contentHeight - height;
                        }

                        StyledText {
                            id: logText

                            width: logFlickable.width
                            text: root.updateLogs
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }

        Process {
            id: logoutProcess

            command: ["qdbus6", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logout"]
        }

        Process {
            id: backupFolderProcess

            command: ["sh", "-c",
                'dir="$1"; shift; mkdir -p "$dir" && exec "$@" "$dir"',
                "--",
                Paths.absolutePath("~/.config/caelestia-update/backups")
            ].concat(GlobalConfig.general.apps.explorer)
        }
    }
}
