pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.nexus.common

VerticalFadeListView {
    id: root

    required property NexusState nState
    readonly property string normalizedQuery: root.nState.searchQuery.trim().toLowerCase()

    signal entrySelected(var entry)

    function moveUp(): void {
        if (count === 0) return;
        currentIndex = Math.max(0, currentIndex - 1);
        positionViewAtIndex(currentIndex, ListView.Contain);
    }

    function moveDown(): void {
        if (count === 0) return;
        currentIndex = Math.min(count - 1, currentIndex + 1);
        positionViewAtIndex(currentIndex, ListView.Contain);
    }

    function executeSelected(): void {
        if (count > 0 && currentIndex >= 0 && currentIndex < count) {
            const entry = model[currentIndex];
            root.nState.goToSubPage(entry.pageIdx, entry.subPageIdx);
            root.entrySelected(entry);
            root.nState.searchQuery = "";
        }
    }

    model: PageRegistry.fuzzyEntries(root.normalizedQuery)
    currentIndex: 0

    topMargin: Tokens.padding.large
    bottomMargin: Tokens.padding.large
    spacing: Tokens.spacing.extraSmall
    clip: true

    focus: true

    onNormalizedQueryChanged: currentIndex = 0

    Keys.onUpPressed: moveUp()
    Keys.onDownPressed: moveDown()
    Keys.onReturnPressed: executeSelected()

    delegate: StyledRect {
        id: item

        required property var modelData
        required property int index

        readonly property string settingLabel: modelData.settingLabel
        readonly property string pageLabel: modelData.pageLabel
        readonly property string pageIcon: modelData.pageIcon
        readonly property int pageIdx: modelData.pageIdx
        readonly property int subPageIdx: modelData.subPageIdx

        readonly property bool isSelected: index === root.currentIndex

        width: root.width
        implicitHeight: {
            const h = layout.implicitHeight + layout.anchors.margins * 2;
            return h % 2 === 0 ? h : h + 1;
        }

        color: isSelected
            ? Colours.palette.m3secondaryContainer
            : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        border.width: isSelected ? 2 : 0
        border.color: Colours.palette.m3primary

        radius: isSelected ? Tokens.rounding.extraLargeIncreased : Tokens.rounding.large
        opacity: 0

        transform: Translate {
            id: slideTrans

            x: -24
        }

        Component.onCompleted: {
            if (Tokens.anim.enabled && !root.moving && !root.dragging) {
                slideAnim.start();
            } else {
                slideTrans.x = 0;
                item.opacity = 1;
            }
        }

        Behavior on radius {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on color {
            CAnim {}
        }

        Behavior on border.width {
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
                root.currentIndex = item.index;
                const entry = item.modelData;
                root.nState.goToSubPage(item.pageIdx, item.subPageIdx);
                root.entrySelected(entry);
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
                color: item.isSelected ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                Behavior on color {
                    CAnim {}
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: Centering.pixelAlign(parent.height, height)

                    text: item.pageIcon
                    color: item.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                    grade: 25

                    Behavior on color {
                        CAnim {}
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: item.settingLabel
                    font: Tokens.font.body.medium
                    color: item.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("in ") + item.pageLabel
                    color: item.isSelected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    font: NexusStyle.secondaryFont
                    elide: Text.ElideRight
                }
            }

            MaterialIcon {
                text: "chevron_right"
                color: item.isSelected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
                opacity: item.isSelected ? 1 : 0.6

                Behavior on color {
                    CAnim {}
                }
            }
        }

        SequentialAnimation {
            id: slideAnim

            PauseAnimation {
                duration: Math.min(item.index * 24, 200)
            }

            ParallelAnimation {
                Anim {
                    target: slideTrans
                    property: "x"
                    from: -24
                    to: 0
                    type: Anim.FastSpatial
                }

                Anim {
                    target: item
                    property: "opacity"
                    from: 0
                    to: 1
                    type: Anim.DefaultEffects
                }
            }
        }
    }
}
