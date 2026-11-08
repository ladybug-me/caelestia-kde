pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property var entries
    property string selectedId: ""

    property string selectActionLabel: ""

    property bool expanded: false
    property bool internalShown: false
    property int collapsedPerGroup: 3

    readonly property bool richMode: root.entries.some(e => !e.isRelease && (!!e.author || !!e.subject))
    readonly property int rowHeight: root.richMode ? 56 : 44
    readonly property int headerHeight: 30
    readonly property int actionHeight: 40
    readonly property int gutterWidth: 26
    readonly property int textIndent: root.gutterWidth + Tokens.spacing.small
    readonly property real dotRadius: 5
    readonly property real currentDotRadius: 9

    readonly property var internalTypes: ["refactor", "style", "docs", "test", "build", "ci", "chore"]
    readonly property int internalCount: root.entries.filter(e => root.isInternal(e)).length
    readonly property var visibleEntries: root.internalShown ? root.entries : root.entries.filter(e => !root.isInternal(e))
    readonly property var rows: root.buildRows()
    readonly property int contentHeight: root.rows.length === 0 ? 0 : root.rows[root.rows.length - 1].y + root.rows[root.rows.length - 1].height

    readonly property var thread: {
        let top = -1;
        let bottom = -1;
        for (let i = 0; i < root.rows.length; i++) {
            const r = root.rows[i];
            if (r.kind !== "entry")
                continue;
            const centre = r.y + r.height / 2;
            if (top < 0)
                top = centre;
            bottom = centre;
        }
        return { top: top, bottom: bottom };
    }

    readonly property var commitTypes: ({
        feat: { label: qsTr("New"), color: Colours.palette.m3primary },
        fix: { label: qsTr("Fixed"), color: Colours.palette.m3error },
        perf: { label: qsTr("Faster"), color: Colours.palette.m3secondaryFixedDim },
        refactor: { label: qsTr("Refactor"), color: Colours.palette.m3secondary },
        style: { label: qsTr("Style"), color: Colours.palette.m3tertiaryFixedDim },
        docs: { label: qsTr("Docs"), color: Colours.palette.m3tertiary },
        test: { label: qsTr("Tests"), color: Colours.palette.m3primaryFixedDim },
        build: { label: qsTr("Build"), color: Colours.palette.m3outline },
        ci: { label: qsTr("CI"), color: Colours.palette.m3outline },
        chore: { label: qsTr("Chore"), color: Colours.palette.m3outline },
        revert: { label: qsTr("Reverted"), color: Colours.palette.m3error }
    })

    signal entryClicked(string entryId, string entryState)
    signal installRequested
    signal selectionCleared

    function commitTypeName(subject): string {
        const match = /^(\w+)(\([^)]*\))?!?:\s*/.exec(subject || "");
        return match ? match[1].toLowerCase() : "";
    }

    function typeInfo(subject): var {
        return root.commitTypes[root.commitTypeName(subject)] || null;
    }

    function isInternal(entry): bool {
        if (!entry || entry.isRelease || entry.state === "current")
            return false;
        if (entry.isMerge)
            return true;
        return root.internalTypes.indexOf(root.commitTypeName(entry.subject)) >= 0;
    }

    function typeStrippedSubject(subject): string {
        const stripped = (subject || "").replace(/^\w+(\([^)]*\))?!?:\s*/, "");
        return stripped === "" ? (subject || "") : stripped;
    }

    function mergedSubject(subject): string {
        const match = /^Merge pull request #(\d+) from [^/]+\/(.+)$/.exec(subject || "");
        if (!match)
            return subject || "";
        return "#" + match[1] + " · " + match[2];
    }

    function stateLabel(state): string {
        if (state === "available")
            return qsTr("Available");
        if (state === "current")
            return qsTr("Current");
        return qsTr("Past");
    }

    function collapsedLimit(state): int {
        if (!root.richMode)
            return root.collapsedPerGroup;
        return state === "past" ? 0 : 1;
    }

    function buildRows(): var {
        const groups = [
            { title: "", state: "available" },
            { title: qsTr("Your version"), state: "current" },
            { title: qsTr("Earlier"), state: "past" }
        ];
        const rows = [];
        let y = 0;
        let hidden = 0;
        let overLimit = false;

        for (let g = 0; g < groups.length; g++) {
            const list = root.visibleEntries.filter(e => e.state === groups[g].state);
            if (list.length === 0)
                continue;

            const cap = root.collapsedLimit(groups[g].state);
            if (list.length > cap)
                overLimit = true;
            const limit = root.expanded ? list.length : Math.min(list.length, cap);
            hidden += list.length - limit;
            if (limit === 0)
                continue;

            if (groups[g].title !== "") {
                rows.push({ kind: "header", label: groups[g].title, y: y, height: root.headerHeight });
                y += root.headerHeight;
            }
            for (let i = 0; i < limit; i++) {
                rows.push({ kind: "entry", entry: list[i], y: y, height: root.rowHeight });
                y += root.rowHeight;
                if (list[i].id === root.selectedId && root.selectActionLabel !== "") {
                    rows.push({ kind: "action", action: "install", label: root.selectActionLabel, icon: "system_update_alt", y: y, height: root.actionHeight });
                    y += root.actionHeight;
                    rows.push({ kind: "action", action: "clear", label: qsTr("Clear selection"), icon: "close", y: y, height: root.actionHeight });
                    y += root.actionHeight;
                }
            }
        }

        if (!root.expanded && hidden > 0) {
            rows.push({
                kind: "action",
                action: "expand",
                label: root.richMode ? qsTr("Show all commits (%1)").arg(hidden) : qsTr("Show all (%1 more)").arg(hidden),
                icon: "expand_more",
                y: y,
                height: root.actionHeight
            });
            y += root.actionHeight;
        } else if (root.expanded && overLimit) {
            rows.push({ kind: "action", action: "collapse", label: qsTr("Show less"), icon: "expand_less", y: y, height: root.actionHeight });
            y += root.actionHeight;
        }

        if (root.internalCount > 0) {
            rows.push({
                kind: "action",
                action: "internal",
                label: root.internalShown ? qsTr("Hide internal changes") : qsTr("Show internal changes (%1)").arg(root.internalCount),
                icon: root.internalShown ? "visibility_off" : "visibility",
                y: y,
                height: root.actionHeight
            });
            y += root.actionHeight;
        }

        return rows;
    }

    implicitWidth: 200
    implicitHeight: root.contentHeight

    Rectangle {
        visible: root.thread.bottom > root.thread.top
        x: root.gutterWidth / 2 - 1
        y: root.thread.top
        width: 2
        height: root.thread.bottom - root.thread.top
        color: Colours.palette.m3outlineVariant
        opacity: 0.6
    }

    Repeater {
        model: root.rows

        delegate: Item {
            id: row

            required property var modelData

            readonly property string kind: modelData.kind
            readonly property var entry: row.kind === "entry" ? modelData.entry : null
            readonly property bool isCurrent: row.entry !== null && row.entry.state === "current"
            readonly property bool isAvailable: row.entry !== null && row.entry.state === "available"
            readonly property bool isPast: row.entry !== null && row.entry.state === "past"
            readonly property bool entrySelected: row.entry !== null && root.selectedId === row.entry.id
            readonly property bool isMerge: row.entry !== null && !!row.entry.isMerge
            readonly property bool isRelease: row.entry !== null && !!row.entry.isRelease
            readonly property var typeInfo: row.entry !== null && !row.isRelease && !row.isMerge ? root.typeInfo(row.entry.subject) : null
            readonly property string title: {
                if (row.kind === "header" || row.kind === "action")
                    return modelData.label;
                if (row.isRelease)
                    return row.entry.label;
                return row.isMerge ? root.mergedSubject(row.entry.subject) : root.typeStrippedSubject(row.entry.subject);
            }
            readonly property string metaLine: {
                if (row.entry === null)
                    return "";
                const parts = [];
                if (!row.isRelease && row.entry.label !== "")
                    parts.push(row.entry.label);
                if (row.tooltipText !== "")
                    parts.push(row.tooltipText);
                return parts.join(" · ");
            }
            readonly property bool isAction: row.kind === "action"
            readonly property bool isInteractive: row.kind === "entry" || row.isAction
            readonly property color accentColour: {
                if (!row.isRelease && row.typeInfo !== null)
                    return row.typeInfo.color;
                return Colours.palette.m3primary;
            }
            readonly property string tooltipText: {
                if (row.entry === null)
                    return "";
                const author = row.entry.author || "";
                const date = row.entry.date || "";
                if (author === "" && date === "")
                    return "";
                return author !== "" && date !== "" ? `${author} • ${date}` : (author || date);
            }

            property bool hovered: false

            signal clicked

            function activate(): void {
                if (row.kind === "entry") {
                    root.entryClicked(row.entry.id, row.entry.state);
                } else if (row.kind === "action") {
                    const action = row.modelData.action;
                    if (action === "internal")
                        root.internalShown = !root.internalShown;
                    else if (action === "install")
                        root.installRequested();
                    else if (action === "clear")
                        root.selectionCleared();
                    else
                        root.expanded = !root.expanded;
                }
            }

            x: 0
            y: modelData.y
            width: root.width
            height: modelData.height
            activeFocusOnTab: row.isInteractive
            enabled: row.isInteractive
            Accessible.role: row.isAction ? Accessible.Button : Accessible.ListItem
            Accessible.name: row.entry !== null ? `${root.stateLabel(row.entry.state)}: ${row.title}` : row.title
            Accessible.description: row.metaLine
            Accessible.selected: row.entrySelected
            Accessible.onPressAction: row.clicked()
            onClicked: row.activate()

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    row.activate();
                    event.accepted = true;
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Tokens.rounding.extraSmall
                color: Colours.palette.m3onSurface
                opacity: row.hovered && row.isInteractive ? 0.07 : 0.0

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Tokens.rounding.extraSmall
                color: "transparent"
                border.width: 2
                border.color: Colours.palette.m3primary
                visible: row.activeFocus
            }

            StyledText {
                visible: row.kind === "header"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.textIndent
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: row.title
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }

            RowLayout {
                visible: row.isAction
                anchors.fill: parent
                anchors.leftMargin: root.textIndent
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: row.modelData.icon || "expand_more"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: row.title
                    color: Colours.palette.m3primary
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                visible: row.isCurrent
                x: root.gutterWidth / 2 - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: root.currentDotRadius * 4
                height: width
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary
                opacity: 0.15
            }

            Rectangle {
                visible: row.entrySelected
                x: root.gutterWidth / 2 - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: root.currentDotRadius * 3
                height: width
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary
                opacity: 0.22
            }

            Rectangle {
                readonly property real r: row.isCurrent ? root.currentDotRadius : root.dotRadius

                visible: row.kind === "entry"
                x: root.gutterWidth / 2 - r
                anchors.verticalCenter: parent.verticalCenter
                width: r * 2
                height: r * 2
                radius: row.isMerge ? 2 : r
                rotation: row.isMerge ? 45 : 0
                color: {
                    if (row.isCurrent || row.entrySelected) return Colours.palette.m3primary;
                    if (row.isAvailable) return "transparent";
                    return row.isRelease ? Colours.palette.m3outlineVariant : (row.typeInfo ? row.typeInfo.color : Colours.palette.m3outlineVariant);
                }
                opacity: row.isPast && !row.isRelease ? 0.85 : 1
                border.color: row.isAvailable && !row.entrySelected ? row.accentColour : "transparent"
                border.width: row.isAvailable && !row.entrySelected ? 2 : 0

                Behavior on color {
                    CAnim {}
                }
                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
                Behavior on border.color {
                    CAnim {}
                }
            }

            Column {
                visible: row.kind === "entry"
                anchors {
                    left: parent.left
                    leftMargin: root.textIndent
                    right: parent.right
                    rightMargin: Tokens.padding.medium
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2

                RowLayout {
                    width: parent.width
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        visible: row.isRelease
                        fontStyle: Tokens.font.icon.small
                        text: "sell"
                        color: (row.isCurrent || row.entrySelected) ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.title
                        font: row.isCurrent ? Tokens.font.body.medium : Tokens.font.body.small
                        color: {
                            if (row.isCurrent || row.entrySelected) return Colours.palette.m3primary;
                            if (row.isRelease) return row.isAvailable ? Colours.palette.m3onSurface : Colours.palette.m3outline;
                            return row.isMerge ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface;
                        }
                        elide: Text.ElideRight

                        Behavior on color {
                            CAnim {}
                        }
                    }

                    StyledRect {
                        visible: row.typeInfo !== null
                        Layout.alignment: Qt.AlignVCenter
                        color: Qt.alpha(row.accentColour, 0.22)
                        radius: Tokens.rounding.full
                        implicitWidth: chipText.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: chipText.implicitHeight + Tokens.padding.extraSmall

                        StyledText {
                            id: chipText

                            anchors.centerIn: parent
                            text: row.typeInfo ? row.typeInfo.label : ""
                            font: NexusStyle.secondaryFont
                            color: row.accentColour
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: row.metaLine !== ""
                    text: row.metaLine
                    font: NexusStyle.secondaryFont
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: row.isInteractive
                hoverEnabled: true
                cursorShape: row.isInteractive ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: row.hovered = true
                onExited: row.hovered = false
                onClicked: row.clicked()
            }

            Loader {
                asynchronous: true
                active: row.kind === "entry" && row.tooltipText !== ""
                z: 10000
                sourceComponent: Component {
                    Tooltip {
                        target: row
                        text: row.tooltipText
                    }
                }
            }
        }
    }
}
