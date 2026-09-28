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

    readonly property bool richMode: root.entries.some(e => !e.isRelease && (!!e.author || !!e.subject))

    readonly property int rowHeight: root.richMode ? 56 : 44

    readonly property int gutterWidth: 32

    readonly property real dotRadius: root.richMode ? 6 : 5

    readonly property real currentDotRadius: 10

    readonly property var commitTypes: ({
        feat: { label: qsTr("feat"), color: Colours.palette.m3primary },
        fix: { label: qsTr("fix"), color: Colours.palette.m3error },
        perf: { label: qsTr("perf"), color: Colours.palette.m3secondaryFixedDim },
        refactor: { label: qsTr("refactor"), color: Colours.palette.m3secondary },
        style: { label: qsTr("style"), color: Colours.palette.m3tertiaryFixedDim },
        docs: { label: qsTr("docs"), color: Colours.palette.m3tertiary },
        test: { label: qsTr("test"), color: Colours.palette.m3primaryFixedDim },
        build: { label: qsTr("build"), color: Colours.palette.m3outline },
        ci: { label: qsTr("ci"), color: Colours.palette.m3outline },
        chore: { label: qsTr("chore"), color: Colours.palette.m3outline },
        revert: { label: qsTr("revert"), color: Colours.palette.m3error }
    })

    signal entryClicked(string entryId, string entryState)

    function commitType(subject) {
        const match = /^(\w+)(\([^)]*\))?!?:\s*/.exec(subject || "");
        if (!match)
            return null;
        return root.commitTypes[match[1].toLowerCase()] || null;
    }

    // The type chip already shows "fix", so drop the prefix from the line the
    // reader actually reads: "fix(recorder): scope the gif" reads as noise twice.
    function typeStrippedSubject(subject) {
        const stripped = (subject || "").replace(/^\w+(\([^)]*\))?!?:\s*/, "");
        return stripped === "" ? (subject || "") : stripped;
    }

    function mergedSubject(subject) {
        const match = /^Merge pull request #(\d+) from [^/]+\/(.+)$/.exec(subject || "");
        if (!match)
            return subject || "";
        return "#" + match[1] + " · " + match[2];
    }

    implicitWidth: 200
    implicitHeight: root.entries.length * root.rowHeight

    Rectangle {
        visible: root.entries.length > 1
        x: root.gutterWidth / 2 - 1
        y: root.rowHeight / 2
        width: 2
        height: Math.max(0, root.entries.length - 1) * root.rowHeight
        color: Colours.palette.m3outlineVariant
        opacity: 0.6
    }

    Repeater {
        model: root.entries

        delegate: Item {
            id: entry

            required property int index
            required property var modelData

            readonly property bool isCurrent: modelData.state === "current"
            readonly property bool isAvailable: modelData.state === "available"
            readonly property bool isPast: modelData.state === "past"
            readonly property bool isSelected: root.selectedId === modelData.id
            readonly property bool isClickable: (isAvailable || isPast || isCurrent) && modelData.id !== "##current##"
            readonly property bool isMerge: !!modelData.isMerge
            readonly property bool isRelease: !!modelData.isRelease
            // Conventional-commit prefix (feat/fix/…) parsed from the subject —
            // null for merges, releases, or subjects that don't follow the
            // convention, in which case the dot falls back to a neutral tone.
            readonly property var typeInfo: (!isRelease && !isMerge) ? root.commitType(modelData.subject) : null
            readonly property string displaySubject: {
                if (isRelease || !modelData.subject)
                    return "";
                return isMerge ? root.mergedSubject(modelData.subject) : root.typeStrippedSubject(modelData.subject);
            }
            readonly property string metaLine: {
                const parts = [];
                if (!isRelease && modelData.label !== "")
                    parts.push(modelData.label);
                if (entry.tooltipText !== "")
                    parts.push(entry.tooltipText);
                return parts.join(" · ");
            }
            readonly property color typeColor: {
                if (isMerge) return Colours.palette.m3secondaryFixedDim;
                if (typeInfo) return typeInfo.color;
                return Colours.palette.m3outlineVariant;
            }
            readonly property string tooltipText: {
                const author = modelData.author || "";
                const date = modelData.date || "";
                if (author === "" && date === "")
                    return "";
                return author !== "" && date !== "" ? `${author} • ${date}` : (author || date);
            }

            property bool hovered: false

            x: 0
            y: index * root.rowHeight
            width: root.width
            height: root.rowHeight

            Rectangle {
                anchors.fill: parent
                radius: Tokens.rounding.extraSmall
                color: Colours.palette.m3onSurface
                opacity: entry.hovered && entry.isClickable ? 0.07 : 0.0

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
            }

            Rectangle {
                visible: entry.isCurrent
                x: root.gutterWidth / 2 - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: root.currentDotRadius * 4
                height: width
                radius: width / 2
                color: Colours.palette.m3primary
                opacity: 0.15
            }

            Rectangle {
                visible: entry.isSelected
                x: root.gutterWidth / 2 - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: root.currentDotRadius * 3
                height: width
                radius: width / 2
                color: Colours.palette.m3primary
                opacity: 0.22
            }

            Rectangle {
                id: dot

                readonly property real r: entry.isCurrent ? root.currentDotRadius : root.dotRadius

                x: root.gutterWidth / 2 - r
                anchors.verticalCenter: parent.verticalCenter
                width: r * 2
                height: r * 2
                radius: entry.isMerge ? 2 : r
                rotation: entry.isMerge ? 45 : 0

                color: {
                    if (entry.isCurrent || entry.isSelected) return Colours.palette.m3primary;
                    return entry.isRelease ? Colours.palette.m3outlineVariant : entry.typeColor;
                }
                opacity: (entry.isAvailable && !entry.isSelected) ? 0 : (entry.isPast && !entry.isRelease ? 0.85 : 1)
                border.color: {
                    if (!entry.isAvailable || entry.isSelected) return "transparent";
                    return entry.isRelease ? Colours.palette.m3primary : entry.typeColor;
                }
                border.width: (entry.isAvailable && !entry.isSelected) ? 2 : 0

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
                anchors {
                    left: parent.left
                    leftMargin: root.gutterWidth + Tokens.spacing.medium
                    right: parent.right
                    rightMargin: Tokens.padding.medium
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2

                RowLayout {
                    width: parent.width
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        visible: entry.isRelease
                        fontStyle: Tokens.font.icon.small
                        text: "sell"
                        color: (entry.isCurrent || entry.isSelected) ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: entry.isRelease ? entry.modelData.label : entry.displaySubject
                        font: entry.isCurrent ? Tokens.font.body.medium : Tokens.font.body.small
                        color: {
                            if (entry.isCurrent || entry.isSelected) return Colours.palette.m3primary;
                            if (entry.isRelease) return entry.isAvailable ? Colours.palette.m3onSurface : Colours.palette.m3outline;
                            return entry.isMerge ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface;
                        }
                        elide: Text.ElideRight

                        Behavior on color {
                            CAnim {}
                        }
                    }

                    StyledRect {
                        visible: entry.typeInfo !== null
                        Layout.alignment: Qt.AlignVCenter
                        color: Qt.alpha(entry.typeColor, 0.22)
                        radius: Tokens.rounding.full
                        implicitWidth: chipText.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: chipText.implicitHeight + Tokens.padding.extraSmall

                        StyledText {
                            id: chipText

                            anchors.centerIn: parent
                            text: entry.typeInfo ? entry.typeInfo.label : ""
                            font: Tokens.font.label.small
                            color: entry.typeColor
                        }
                    }

                    StyledRect {
                        visible: entry.isMerge
                        Layout.alignment: Qt.AlignVCenter
                        color: Qt.alpha(entry.typeColor, 0.18)
                        radius: Tokens.rounding.full
                        implicitWidth: mergeText.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: mergeText.implicitHeight + Tokens.padding.extraSmall

                        StyledText {
                            id: mergeText

                            anchors.centerIn: parent
                            text: qsTr("merge")
                            font: Tokens.font.label.small
                            color: entry.typeColor
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: entry.metaLine !== ""
                    text: entry.metaLine
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: entry.isClickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: entry.hovered = true
                onExited: entry.hovered = false
                onClicked: {
                    if (entry.isClickable) {
                        root.entryClicked(entry.modelData.id, entry.modelData.state);
                    }
                }
            }

            Loader {
                asynchronous: true
                active: entry.tooltipText !== ""
                z: 10000
                sourceComponent: Component {
                    Tooltip {
                        target: entry
                        text: entry.tooltipText
                    }
                }
            }
        }
    }
}
