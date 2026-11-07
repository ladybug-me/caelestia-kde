pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.nexus
import qs.modules.nexus.common

VerticalFadeFlickable {
    id: root

    required property NexusState nState
    readonly property var filteredPages: PageRegistry.allPages
    property int selectedIndex: 0
    property bool selectionActive: false

    function moveUp(): void {
        const pages = root.filteredPages;
        if (!pages || pages.length === 0)
            return;
        root.selectionActive = true;
        root.selectedIndex = root.selectedIndex > 0 ? root.selectedIndex - 1 : pages.length - 1;
        ensureVisible(list.itemAt(root.selectedIndex));
    }

    function moveDown(): void {
        const pages = root.filteredPages;
        if (!pages || pages.length === 0)
            return;
        root.selectionActive = true;
        root.selectedIndex = (root.selectedIndex >= 0 && root.selectedIndex < pages.length - 1) ? root.selectedIndex + 1 : 0;
        ensureVisible(list.itemAt(root.selectedIndex));
    }

    function activateSelected(): void {
        if (!root.selectionActive)
            return;
        const pages = root.filteredPages;
        if (!pages || root.selectedIndex < 0 || root.selectedIndex >= pages.length)
            return;
        root.selectionActive = false;
        root.nState.goToPage(pages[root.selectedIndex].pageIdx);
        if (root.nState.compact)
            root.nState.enterCompactPage();
    }

    function clearSelection(): void {
        root.selectionActive = false;
    }

    function selectCurrentOrFirst(): void {
        root.selectionActive = true;
        const pages = root.filteredPages;
        if (!pages || pages.length === 0)
            return;
        const idx = pages.findIndex(p => p.pageIdx === root.nState.currentPageIdx);
        root.selectedIndex = idx >= 0 ? idx : 0;
        ensureVisible(list.itemAt(root.selectedIndex));
    }

    function ensureVisible(item: Item): void {
        if (!item)
            return;
        const top = item.y;
        const bottom = item.y + item.height;
        if (top < root.contentY) {
            root.contentY = top;
        } else if (bottom > root.contentY + root.height) {
            root.contentY = bottom - root.height;
        }
    }

    topMargin: 0
    bottomMargin: Tokens.padding.large
    contentHeight: content.implicitHeight
    focus: true

    Keys.onUpPressed: moveUp()
    Keys.onDownPressed: moveDown()
    Keys.onReturnPressed: activateSelected()
    Keys.onEnterPressed: activateSelected()
    Keys.onRightPressed: activateSelected()

    Component.onCompleted: {
        root.selectionActive = false;
        const pages = root.filteredPages;
        if (!pages)
            return;
        const idx = pages.findIndex(p => p.pageIdx === root.nState.currentPageIdx);
        if (idx >= 0)
            root.selectedIndex = idx;
    }

    Connections {
        function onCurrentPageIdxChanged(): void {
            root.selectionActive = false;
            const pages = root.filteredPages;
            if (!pages)
                return;
            const idx = pages.findIndex(p => p.pageIdx === root.nState.currentPageIdx);
            if (idx >= 0)
                root.selectedIndex = idx;
        }

        target: root.nState
    }

    TapHandler {
        onTapped: {
            root.selectionActive = false;
            root.focus = true;
        }
    }

    ColumnLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.small

        Repeater {
            id: list

            model: root.filteredPages

            StyledRect {
                id: item

                required property var modelData
                required property int index
                readonly property var page: modelData.page
                readonly property int pageIdx: modelData.pageIdx

                readonly property bool isCurrentPage: pageIdx === root.nState.currentPageIdx
                readonly property bool isSelected: root.selectionActive && index === root.selectedIndex

                Layout.fillWidth: true
                implicitHeight: 66

                color: isCurrentPage
                    ? Colours.palette.m3secondaryContainer
                    : isSelected
                        ? Colours.layer(Colours.palette.m3surfaceContainerHigh, 4)
                        : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                border.width: isSelected ? 2 : 0
                border.color: Colours.palette.m3primary
                radius: stateLayer.pressed ? Tokens.rounding.medium : Tokens.rounding.large

                Behavior on radius {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                StateLayer {
                    id: stateLayer

                    anchors.fill: parent
                    radius: parent.radius
                    manualHoverOverride: item.isSelected

                    onClicked: {
                        root.selectionActive = false;
                        root.selectedIndex = item.index;
                        root.nState.goToPage(item.pageIdx);
                        if (root.nState.compact)
                            root.nState.enterCompactPage();
                    }
                }

                StyledRect {
                    visible: item.isCurrentPage

                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.extraSmall
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 22
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary
                }

                RowLayout {
                    id: layout

                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    anchors.topMargin: Tokens.padding.small
                    anchors.bottomMargin: Tokens.padding.small
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 34
                        implicitHeight: 34

                        radius: Tokens.rounding.full
                        color: item.isCurrentPage ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 1

                            text: item.page.icon
                            color: item.isCurrentPage ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                            fontStyle: Tokens.font.icon.small
                            grade: 25
                            fill: item.page.noFill ? 0 : 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            text: item.page.label
                            font: Tokens.font.body.builders.medium.size(Math.round(Tokens.font.body.medium.pointSize * 0.92)).build()
                            color: item.isCurrentPage ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: item.page.description
                            color: item.isCurrentPage ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.builders.small.size(9).build()
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    component RadiusBehavior: Behavior {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
