pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import "updateModel.js" as UpdateModel

// The history the check returned, grouped by what it means for the reader. The
// page owns what is shown and what is selected; this renders it. A selected row
// grows to hold its own action, and the column reflows, so choosing a version
// never rebuilds the list or moves keyboard focus.
Item {
    id: root

    required property var entries
    property string selectedId: ""
    property var selectAction: null

    readonly property bool commitList: UpdateModel.isCommitList(root.entries)
    readonly property int rowHeight: root.commitList ? 56 : 44
    readonly property int headerHeight: 30
    readonly property int actionHeight: 40
    readonly property int gutterWidth: 26
    readonly property int textIndent: root.gutterWidth + Tokens.spacing.small

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

    // The rows to render, and whether each one sits between two entries - the
    // thread the dots hang from. Nothing here depends on the selection.
    readonly property var rows: {
        const rows = [];
        const available = root.entries.filter(e => e.state === "available");
        for (let i = 0; i < available.length; i++)
            rows.push({ kind: "entry", entry: available[i] });

        const groups = [
            { title: qsTr("Your version"), state: "current" },
            { title: qsTr("Earlier"), state: "past" }
        ];
        for (let g = 0; g < groups.length; g++) {
            const group = root.entries.filter(e => e.state === groups[g].state);
            if (group.length === 0)
                continue;
            rows.push({ kind: "header", title: groups[g].title });
            for (let i = 0; i < group.length; i++)
                rows.push({ kind: "entry", entry: group[i] });
        }

        let above = false;
        for (let i = 0; i < rows.length; i++) {
            rows[i].hasAbove = above;
            if (rows[i].kind === "entry")
                above = true;
        }

        let below = false;
        for (let i = rows.length - 1; i >= 0; i--) {
            rows[i].hasBelow = below;
            if (rows[i].kind === "entry")
                below = true;
        }

        return rows;
    }

    signal entryClicked(string entryId, string entryState)
    signal actionRequested(string key)

    function typeLabel(type): string {
        const info = root.commitTypes[type];
        return info ? info.label : "";
    }

    function typeColour(type): color {
        const info = root.commitTypes[type];
        return info ? info.color : Colours.palette.m3outlineVariant;
    }

    function stateLabel(state): string {
        if (state === "available")
            return qsTr("Available");
        if (state === "current")
            return qsTr("Current");
        return qsTr("Past");
    }

    implicitWidth: 200
    implicitHeight: column.implicitHeight

    Column {
        id: column

        width: parent.width

        Repeater {
            model: root.rows

            delegate: Item {
                id: row

                required property int index
                required property var modelData

                readonly property bool isHeader: modelData.kind === "header"
                readonly property var entry: row.isHeader ? null : modelData.entry
                readonly property bool isCurrent: row.entry !== null && row.entry.state === "current"
                readonly property bool isAvailable: row.entry !== null && row.entry.state === "available"
                readonly property bool isPast: row.entry !== null && row.entry.state === "past"
                readonly property bool entrySelected: row.entry !== null && root.selectedId === row.entry.id
                readonly property bool isMerge: row.entry !== null && row.entry.isMerge
                readonly property bool isRelease: row.entry !== null && row.entry.isRelease
                readonly property string typeLabel: row.entry !== null ? root.typeLabel(row.entry.type) : ""
                readonly property color accent: row.entry !== null ? root.typeColour(row.entry.type) : Colours.palette.m3primary
                readonly property string metaLine: {
                    if (row.entry === null)
                        return "";
                    const parts = [];
                    if (!row.isRelease && row.entry.label !== "")
                        parts.push(row.entry.label);
                    if (row.entry.author !== "" && row.entry.date !== "")
                        parts.push(`${row.entry.author} • ${row.entry.date}`);
                    else if (row.entry.author !== "" || row.entry.date !== "")
                        parts.push(row.entry.author || row.entry.date);
                    return parts.join(" · ");
                }

                property bool hovered: false

                signal clicked

                function activate(): void {
                    if (row.isHeader)
                        return;
                    root.entryClicked(row.entry.id, row.entry.state);
                }

                width: column.width
                height: row.isHeader ? root.headerHeight : (root.rowHeight + (row.entrySelected ? root.actionHeight : 0))
                activeFocusOnTab: !row.isHeader
                Accessible.role: Accessible.ListItem
                Accessible.name: row.isHeader ? modelData.title : `${root.stateLabel(row.entry.state)}: ${row.entry.title}`
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
                    x: root.gutterWidth / 2 - 1
                    y: 0
                    width: 2
                    height: row.height / 2
                    visible: row.modelData.hasAbove
                    color: Colours.palette.m3outlineVariant
                    opacity: 0.6
                }

                Rectangle {
                    x: root.gutterWidth / 2 - 1
                    y: row.height / 2
                    width: 2
                    height: row.height / 2
                    visible: row.modelData.hasBelow
                    color: Colours.palette.m3outlineVariant
                    opacity: 0.6
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.rounding.extraSmall
                    color: Colours.palette.m3onSurface
                    opacity: row.hovered && !row.isHeader ? 0.07 : 0.0

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
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: root.textIndent
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    visible: row.isHeader
                    text: row.isHeader ? modelData.title : ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: dot

                    readonly property real diameter: row.isCurrent ? 18 : 10

                    visible: !row.isHeader
                    x: root.gutterWidth / 2 - diameter / 2
                    y: root.rowHeight / 2 - diameter / 2
                    width: diameter
                    height: diameter
                    z: 1
                    radius: row.isMerge ? 2 : diameter / 2
                    rotation: row.isMerge ? 45 : 0
                    color: {
                        if (row.isCurrent || row.entrySelected)
                            return Colours.palette.m3primary;
                        if (row.isAvailable)
                            return "transparent";
                        if (row.isRelease)
                            return Colours.palette.m3outlineVariant;
                        return row.accent;
                    }
                    opacity: row.isPast && !row.isRelease ? 0.85 : 1
                    border.color: row.isAvailable && !row.entrySelected ? row.accent : "transparent"
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

                Rectangle {
                    visible: !row.isHeader && row.isCurrent
                    x: root.gutterWidth / 2 - width / 2
                    y: root.rowHeight / 2 - height / 2
                    width: 36
                    height: width
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary
                    opacity: 0.15
                }

                Column {
                    visible: !row.isHeader
                    anchors {
                        left: parent.left
                        leftMargin: root.textIndent
                        right: parent.right
                        rightMargin: Tokens.padding.medium
                        top: parent.top
                        topMargin: row.isRelease ? 7 : 10
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
                            text: row.entry !== null ? row.entry.title : ""
                            font: row.isCurrent ? Tokens.font.body.medium : Tokens.font.body.small
                            color: {
                                if (row.isCurrent || row.entrySelected)
                                    return Colours.palette.m3primary;
                                if (row.isRelease)
                                    return row.isAvailable ? Colours.palette.m3onSurface : Colours.palette.m3outline;
                                return row.isMerge ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface;
                            }
                            elide: Text.ElideRight

                            Behavior on color {
                                CAnim {}
                            }
                        }

                        StyledRect {
                            visible: row.typeLabel !== ""
                            Layout.alignment: Qt.AlignVCenter
                            color: Qt.alpha(row.accent, 0.22)
                            radius: Tokens.rounding.full
                            implicitWidth: chip.implicitWidth + Tokens.padding.small * 2
                            implicitHeight: chip.implicitHeight + Tokens.padding.extraSmall

                            StyledText {
                                id: chip

                                anchors.centerIn: parent
                                text: row.typeLabel
                                font: NexusStyle.secondaryFont
                                color: row.accent
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        visible: text !== ""
                        text: row.metaLine
                        font: NexusStyle.secondaryFont
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        width: parent.width
                        visible: row.entrySelected && root.selectAction !== null
                        spacing: Tokens.spacing.small

                        TextButton {
                            text: root.selectAction !== null ? root.selectAction.label : ""
                            type: TextButton.Tonal
                            font: Tokens.font.label.medium
                            horizontalPadding: Tokens.padding.medium
                            verticalPadding: Tokens.padding.extraSmall
                            onClicked: root.actionRequested(root.selectAction.key)
                        }

                        TextButton {
                            text: qsTr("Clear")
                            type: TextButton.Text
                            font: Tokens.font.label.medium
                            horizontalPadding: Tokens.padding.medium
                            verticalPadding: Tokens.padding.extraSmall
                            onClicked: root.actionRequested("clear")
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !row.isHeader
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: row.hovered = true
                    onExited: row.hovered = false
                    onClicked: row.clicked()
                }
            }
        }
    }
}
