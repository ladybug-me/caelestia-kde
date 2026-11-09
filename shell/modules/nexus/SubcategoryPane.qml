pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.nexus.common

ColumnLayout {
    id: root

    required property NexusState nState
    readonly property var currentPage: PageCompRegistry.categories[root.nState.currentPageIdx]
    property int selectedIndex: 0
    property bool selectionActive: false
    property Item selectedCard: null

    function currentCards(): var {
        if (!cardsColumn || !cardsColumn.children)
            return [];
        const cards = [];
        for (let i = 0; i < cardsColumn.children.length; i++) {
            const child = cardsColumn.children[i];
            if (child && child.pageKey !== undefined)
                cards.push(child);
        }
        return cards;
    }

    function syncSelection(): void {
        if (!root.selectionActive) {
            root.selectedCard = null;
            return;
        }
        const cards = currentCards();
        if (cards.length === 0) {
            root.selectedCard = null;
            return;
        }
        if (root.selectedIndex < 0)
            root.selectedIndex = 0;
        else if (root.selectedIndex >= cards.length)
            root.selectedIndex = cards.length - 1;

        root.selectedCard = cards[root.selectedIndex];
        ensureVisible(root.selectedCard);
    }

    function moveUp(): void {
        const cards = currentCards();
        if (cards.length === 0)
            return;
        root.selectionActive = true;
        root.selectedIndex = root.selectedIndex > 0 ? root.selectedIndex - 1 : cards.length - 1;
        syncSelection();
    }

    function moveDown(): void {
        const cards = currentCards();
        if (cards.length === 0)
            return;
        root.selectionActive = true;
        root.selectedIndex = (root.selectedIndex >= 0 && root.selectedIndex < cards.length - 1) ? root.selectedIndex + 1 : 0;
        syncSelection();
    }

    function selectCurrentOrFirst(): void {
        const cards = currentCards();
        if (cards.length === 0)
            return;
        root.selectionActive = true;
        let idx = -1;
        for (let i = 0; i < cards.length; i++) {
            if (cards[i].pageKey === root.nState.activeSubPageKey) {
                idx = i;
                break;
            }
        }
        root.selectedIndex = idx >= 0 ? idx : 0;
        syncSelection();
    }

    function activateSelected(): void {
        if (!root.selectionActive || !root.selectedCard)
            return;
        const card = root.selectedCard;
        if (card.cardEnabled) {
            root.nState.selectSubCategory(card.pageKey);
        }
        root.clearSelection();
    }

    function clearSelection(): void {
        root.selectionActive = false;
        root.selectedCard = null;
    }

    function ensureVisible(item: Item): void {
        if (!item)
            return;
        const pt = flickable.contentItem.mapFromItem(item, 0, 0);
        const top = pt.y;
        const bottom = pt.y + item.height;
        if (top < flickable.contentY) {
            flickable.contentY = top;
        } else if (bottom > flickable.contentY + flickable.height) {
            flickable.contentY = bottom - flickable.height;
        }
    }

    function ensureActiveCardVisible(): void {
        const cards = currentCards();
        for (let i = 0; i < cards.length; i++) {
            if (cards[i].pageKey === root.nState.activeSubPageKey) {
                ensureVisible(cards[i]);
                break;
            }
        }
    }

    spacing: Tokens.spacing.medium

    Connections {
        function onCurrentPageIdxChanged(): void {
            root.clearSelection();
            Qt.callLater(root.ensureActiveCardVisible);
        }

        function onActiveSubPageKeyChanged(): void {
            Qt.callLater(root.ensureActiveCardVisible);
        }

        target: root.nState
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 46

        StyledRect {
            visible: root.nState.compact
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            height: 38
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerHigh

            StateLayer {
                anchors.fill: parent
                radius: parent.radius

                onClicked: root.nState.exitCompactPage()
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: "arrow_back"
                color: Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.medium
            }
        }

        StyledText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: root.nState.compact ? 46 : Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            text: root.currentPage ? root.currentPage.label : ""
            font: Tokens.font.title.builders.large.weight(Font.Medium).build()
            color: Colours.palette.m3onSurface
            elide: Text.ElideRight
        }
    }

    VerticalFadeFlickable {
        id: flickable

        Layout.fillWidth: true
        Layout.fillHeight: true

        topMargin: 0
        bottomMargin: Tokens.padding.large
        contentHeight: cardsColumn.implicitHeight

        StyledRect {
            z: 2
            visible: flickable.contentHeight > flickable.height + 1
            width: 3
            height: Math.max(24, flickable.height * flickable.visibleArea.heightRatio)
            x: flickable.width - Tokens.padding.small
            y: flickable.contentY + flickable.visibleArea.yPosition * flickable.height
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
            opacity: 0.6
        }

        ColumnLayout {
            id: cardsColumn

            readonly property var cat: PageCompRegistry.categories[root.nState.currentPageIdx]
            readonly property var pagesList: cat ? cat.pages : []

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            Repeater {
                model: cardsColumn.pagesList

                SubcategoryCard {
                    required property var modelData

                    icon: modelData.icon
                    label: modelData.label
                    status: modelData.status !== "" ? modelData.status : modelData.description
                    pageKey: modelData.key
                    cardEnabled: modelData.enabled
                }
            }
        }
    }

    component SubcategoryCard: StyledRect {
        id: card

        required property string icon
        required property string label
        property string status: ""
        required property string pageKey
        property bool cardEnabled: true

        readonly property bool isSelected: root.nState.activeSubPageKey === pageKey
        readonly property bool isNavSelected: root.selectedCard === card

        Layout.fillWidth: true
        implicitHeight: 66

        radius: Tokens.rounding.large
        color: isSelected
            ? Colours.palette.m3secondaryContainer
            : isNavSelected
                ? Colours.layer(Colours.palette.m3surfaceContainerHigh, 4)
                : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
        border.color: isNavSelected
            ? Colours.palette.m3primary
            : (isSelected ? Colours.palette.m3outlineVariant : "transparent")
        border.width: isNavSelected ? 2 : (isSelected ? 1 : 0)
        opacity: cardEnabled ? 1.0 : 0.5

        Behavior on color {
            CAnim {}
        }

        Behavior on border.color {
            CAnim {}
        }

        StateLayer {
            id: stateLayer

            anchors.fill: parent
            radius: parent.radius
            enabled: card.cardEnabled
            manualHoverOverride: card.isNavSelected

            onClicked: {
                root.clearSelection();
                root.nState.selectSubCategory(card.pageKey);
            }
        }

        StyledRect {
            visible: card.isSelected
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.extraSmall
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 22
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
        }

        RowLayout {
            id: cardLayout

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
                color: card.isSelected ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1

                    text: card.icon
                    color: card.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.small
                    grade: 25
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: card.label
                    font: Tokens.font.body.builders.medium.size(Math.round(Tokens.font.body.medium.pointSize * 0.92)).build()
                    color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: card.status
                    color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.builders.small.size(9).build()
                    elide: Text.ElideRight
                }
            }

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "chevron_right"
                color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }
    }
}
