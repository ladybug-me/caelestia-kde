pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    /// Reached straight from the IPC (`openPage 5 1`) there is no screen picked yet, so the
    /// list falls back to the one that is actually in use rather than showing nothing.
    readonly property var output: Displays.outputFor(root.nState.selectedOutput) ?? Displays.enabled[0] ?? Displays.connected[0] ?? null
    readonly property var modes: Displays.modesFor(root.output)

    function isCurrent(mode: var): bool {
        return String(mode.id) === String(root.output?.currentModeId ?? "");
    }

    title: qsTr("Resolution & refresh rate")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText {
            Layout.fillWidth: true
            visible: root.modes.length === 0
            text: qsTr("No screen reports any mode to choose from.")
            color: Colours.palette.m3onSurfaceVariant
            font: NexusStyle.secondaryFont
            wrapMode: Text.Wrap
        }

        Repeater {
            model: root.modes

            delegate: RowButton {
                id: modeRow

                required property var modelData
                required property int index

                first: index === 0
                last: index === root.modes.length - 1
                icon: root.isCurrent(modeRow.modelData) ? "check" : "aspect_ratio"
                text: Displays.modeLabel(modeRow.modelData)
                onClicked: {
                    if (!root.isCurrent(modeRow.modelData))
                        Displays.setMode(root.output.name, String(modeRow.modelData.id));
                    root.nState.closeSubPage();
                }
            }
        }
    }
}
