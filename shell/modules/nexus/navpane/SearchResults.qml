pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.utils
import qs.modules.nexus

VerticalFadeFlickable {
    id: root

    required property NexusState nState
    readonly property string normalizedQuery: root.nState.searchQuery.trim().toLowerCase()
    readonly property var filteredEntries: PageRegistry.fuzzyEntries(root.normalizedQuery)
    property int selectedIndex: 0

    topMargin: Tokens.padding.large
    bottomMargin: Tokens.padding.large
    contentHeight: content.implicitHeight

    focus: true

    onNormalizedQueryChanged: selectedIndex = 0

    function moveUp() {
        selectedIndex = Math.max(0, selectedIndex - 1);
        positionViewAtIndex(selectedIndex);
    }

    function moveDown() {
        selectedIndex = Math.min(list.count - 1, selectedIndex + 1);
        positionViewAtIndex(selectedIndex);
    }

    function executeSelected() {
        if (list.count > 0 && selectedIndex >= 0 && selectedIndex < list.count) {
            const entry = root.filteredEntries[selectedIndex];
            root.nState.goToSubPage(entry.pageIdx, entry.subPageIdx);
            root.nState.searchQuery = "";
        }
    }

    Keys.onUpPressed: moveUp()
    Keys.onDownPressed: moveDown()
    Keys.onReturnPressed: executeSelected()

    function positionViewAtIndex(idx) {
        if (idx < 0 || idx >= list.count) return;
        const itemY = idx * (Tokens.spacing.extraSmall + 64);
        if (itemY < contentY) {
            contentY = itemY;
        } else if (itemY + 64 > contentY + height) {
            contentY = itemY + 64 - height;
        }
    }

    ColumnLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.extraSmall

        Repeater {
            id: list

            model: root.filteredEntries

            StyledRect {
                id: item

                required property var modelData
                required property int index

                readonly property string settingLabel: modelData.settingLabel
                readonly property string pageLabel: modelData.pageLabel
                readonly property string pageIcon: modelData.pageIcon
                readonly property int pageIdx: modelData.pageIdx
                readonly property int subPageIdx: modelData.subPageIdx

                readonly property bool isSelected: index === root.selectedIndex

                Layout.fillWidth: true
                implicitHeight: {
                    const h = layout.implicitHeight + layout.anchors.margins * 2;
                    return h % 2 === 0 ? h : h + 1;
                }

                color: isSelected ? Colours.palette.m3secondaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                radius: Tokens.rounding.extraSmall

                StateLayer {
                    id: stateLayer

                    anchors.fill: parent
                    radius: parent.radius

                    onClicked: {
                        root.selectedIndex = item.index;
                        root.nState.goToSubPage(item.pageIdx, item.subPageIdx);
                        root.nState.searchQuery = "";
                    }
                }

                RowLayout {
                    id: layout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        Layout.fillHeight: true
                        Layout.topMargin: -1
                        Layout.bottomMargin: -1
                        implicitWidth: height

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh

                        MaterialIcon {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: Centering.pixelAlign(parent.height, height)

                            text: item.pageIcon
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                            grade: 25
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: item.settingLabel
                            font: Tokens.font.body.medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("in ") + item.pageLabel
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    MaterialIcon {
                        text: "chevron_right"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }
                }
            }
        }
    }
}
