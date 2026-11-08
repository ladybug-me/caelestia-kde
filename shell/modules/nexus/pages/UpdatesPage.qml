pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common
import "../common/updateModel.js" as UpdateModel

PageBase {
    id: root

    readonly property list<MenuItem> branchItems: branchVariants.instances

    readonly property var activeBranchItem: {
        const found = branchItems.find(function(i) {
            return i.text === UpdateChecker.currentBranch;
        });
        return found || (branchItems.length > 0 ? branchItems[0] : null);
    }

    property string selectedVersionId: ""
    property string pendingBranch: ""
    property bool launchFailed: false
    property string backupError: ""
    property bool timelineExpanded: false
    property bool showInternal: false

    property bool configuredTerminalAvailable: true
    property bool konsoleAvailable: false

    readonly property bool branchDataLoading: root.pendingBranch !== "" && UpdateChecker.checkingUpdates
    readonly property bool updaterActive: UpdateChecker.handoff !== UpdateChecker.Handoff.None

    readonly property var entries: UpdateModel.deriveEntries({
        versionSummaryMode: UpdateChecker.versionSummaryMode,
        availableVersions: UpdateChecker.availableVersions,
        currentVersion: UpdateChecker.currentVersion,
        commits: UpdateChecker.commits,
        installedCommitHash: UpdateChecker.installedCommitHash
    })

    readonly property var shown: UpdateModel.disclosure(root.entries, root.timelineExpanded, root.showInternal, 3)

    readonly property var selection: {
        const entry = UpdateModel.entryById(root.entries, root.selectedVersionId);
        return entry === null ? null : {
            state: entry.state,
            label: entry.label
        };
    }

    readonly property var status: UpdateStatus.describe(root.selection, root.launchFailed)

    readonly property var preview: UpdateModel.previewEntry(root.entries, root.selectedVersionId)
    readonly property string notesText: root.preview !== null && root.preview.isRelease ? UpdateModel.formatNotes(root.preview.details) : ""
    readonly property string releaseUrl: root.preview !== null && root.preview.isRelease ? root.preview.url : ""

    // The configured terminal is a bare command and may not be installed - the
    // default is foot, which a KDE box often does not have - so fall back to
    // konsole, KDE's own terminal, instead of launching nothing.
    readonly property list<string> terminalCommand: root.configuredTerminalAvailable ? GlobalConfig.general.apps.terminal : ["konsole"]
    readonly property bool terminalAvailable: root.configuredTerminalAvailable || root.konsoleAvailable
    readonly property bool busy: UpdateChecker.checkingUpdates && root.status.primary === null

    function runAction(key): void {
        if (key === "check") {
            root.checkNow();
        } else if (key === "turnOn") {
            GlobalConfig.general.checkUpdates = true;
            root.checkNow();
        } else if (key === "restore") {
            confirmDialog.open();
        } else if (key === "install" || key === "reinstall" || key === "reopen") {
            root.launchUpdater();
        } else if (key === "copy") {
            root.copyCommand();
        } else if (key === "clear") {
            root.selectedVersionId = "";
        } else if (key === "dismiss") {
            UpdateChecker.dismissHandoff();
        }
    }

    function checkNow(): void {
        root.launchFailed = false;
        UpdateChecker.checkNow();
    }

    function copyCommand(): void {
        const command = UpdateChecker.updaterArgs(root.selectedVersionId).join(" ");
        Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "--", command]);
    }

    // Launch the updater in the user's terminal. The page only reports the
    // handoff; the updater owns its output, progress and escalation prompts.
    function launchUpdater(): void {
        if (!root.terminalAvailable) {
            root.launchFailed = true;
            return;
        }
        const version = root.selectedVersionId !== "" ? root.selectedVersionId : UpdateChecker.handoffVersion;
        root.launchFailed = false;
        root.selectedVersionId = "";
        // Holds the terminal open afterwards: the update restarts the shell and its output is what the user needs to read.
        const hold = 'caelestia-update "$@"; s=$?; printf "\\n[caelestia-update exited with status %s] Press Enter to close..." "$s"; read -r _';
        Launch.exec([...root.terminalCommand, "sh", "-c", hold, "sh", ...UpdateChecker.updaterArgs(version)]);
        UpdateChecker.markHandoff(version);
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
                    text: root.status.icon
                    color: root.status.highlight ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    font: Tokens.font.title.medium
                    color: root.status.highlight ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.status.title
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.status.detail
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                IconTextButton {
                    id: busyButton

                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    visible: root.busy
                    disabled: true
                    text: qsTr("Checking…")
                    type: TextButton.Filled
                    font: Tokens.font.body.medium
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.medium
                    icon: "refresh"

                    RotationAnimation {
                        target: busyButton.iconLabel
                        property: "rotation"
                        running: root.busy && Tokens.anim.enabled
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }

                IconTextButton {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    visible: !root.busy && root.status.primary !== null
                    text: root.status.primary !== null ? root.status.primary.label : ""
                    type: TextButton.Filled
                    font: Tokens.font.body.medium
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.medium
                    icon: root.status.primary !== null ? root.status.primary.icon : ""
                    onClicked: root.runAction(root.status.primary.key)
                }

                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.status.secondary !== null
                    text: root.status.secondary !== null ? root.status.secondary.label : ""
                    type: TextButton.Text
                    font: Tokens.font.body.medium
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.small
                    onClicked: root.runAction(root.status.secondary.key)
                }

                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.status.dismissible
                    text: qsTr("Dismiss")
                    type: TextButton.Text
                    font: Tokens.font.label.medium
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.extraSmall
                    onClicked: root.runAction("dismiss")
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
            visible: !root.branchDataLoading && root.entries.length > 0
            text: root.shown.isCommitList ? qsTr("Commit history") : qsTr("Version history")
        }

        ConnectedRect {
            visible: root.shown.entries.length > 0
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

                entries: root.shown.entries
                selectedId: root.selectedVersionId
                selectAction: root.selection !== null ? root.status.primary : null
                onEntryClicked: (entryId, entryState) => {
                    root.selectedVersionId = root.selectedVersionId === entryId ? "" : entryId;
                }
                onActionRequested: key => root.runAction(key)
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.branchDataLoading
            spacing: Tokens.spacing.small

            TextButton {
                visible: !root.timelineExpanded && root.shown.hiddenByCap > 0
                text: qsTr("Show all commits (%1)").arg(root.shown.hiddenByCap)
                type: TextButton.Tonal
                font: Tokens.font.body.small
                horizontalPadding: Tokens.padding.large
                verticalPadding: Tokens.padding.small
                onClicked: root.timelineExpanded = true
            }

            TextButton {
                visible: root.timelineExpanded && root.shown.capped
                text: qsTr("Show less")
                type: TextButton.Tonal
                font: Tokens.font.body.small
                horizontalPadding: Tokens.padding.large
                verticalPadding: Tokens.padding.small
                onClicked: root.timelineExpanded = false
            }

            TextButton {
                visible: root.shown.internalCount > 0
                text: root.showInternal ? qsTr("Hide internal changes") : qsTr("Show internal changes (%1)").arg(root.shown.internalCount)
                type: TextButton.Text
                font: Tokens.font.body.small
                horizontalPadding: Tokens.padding.large
                verticalPadding: Tokens.padding.small
                onClicked: root.showInternal = !root.showInternal
            }
        }

        TextButton {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.branchDataLoading && root.shown.isCommitList && UpdateChecker.hasMoreCommits
            text: UpdateChecker.loadingMoreCommits ? qsTr("Loading…") : qsTr("Load older commits")
            type: TextButton.Tonal
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.large
            verticalPadding: Tokens.padding.medium
            disabled: UpdateChecker.loadingMoreCommits
            onClicked: UpdateChecker.loadMoreCommits()
        }

        ConnectedRect {
            visible: !root.branchDataLoading && root.entries.length === 0
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
            }
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
                UpdateChecker.checkNow(item.text);
            }
        }

        ToggleRow {
            last: true
            visible: !root.branchDataLoading
            text: qsTr("Check for updates automatically")
            subtext: qsTr("Every 30 minutes, and once when the shell starts")
            reset: ({
                node: GlobalConfig.general,
                setting: "checkUpdates"
            })
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

        Process {
            id: terminalCheck

            command: ["bash", "-c", "command -v \"$1\" >/dev/null 2>&1", "--", GlobalConfig.general.apps.terminal[0] || ""]
            running: true
            onExited: code => {
                root.configuredTerminalAvailable = code === 0;
                if (code === 0)
                    root.launchFailed = false;
            }
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

            toVersion: root.selection !== null ? root.selection.label : ""
            fromVersion: UpdateChecker.currentVersion !== "unknown" ? UpdateChecker.currentVersion : ""
            onConfirmed: root.launchUpdater()
        }
    }
}
