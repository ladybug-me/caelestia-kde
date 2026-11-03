pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.nexus.common

ConnectedRect {
    id: root

    property NexusState nState
    property string pageKey: ""
    property int pageIdx: -1
    property int subPageIdx: -1
    property string trailingIcon: "open_in_new"

    property alias icon: icon.text
    property alias label: label.text
    property alias status: status.text

    signal clicked

    function navigate(): void {
        if (!root.nState)
            return;

        const targetPageIdx = root.pageKey !== ""
            ? PageRegistry.indexForKey(root.pageKey)
            : (root.pageIdx >= 0 ? root.pageIdx : root.nState.currentPageIdx);

        if (targetPageIdx >= 0 && root.subPageIdx >= 0)
            root.nState.goToSubPage(targetPageIdx, root.subPageIdx);
        else if (targetPageIdx >= 0)
            root.nState.goToPage(targetPageIdx);
    }

    Layout.fillWidth: true
    implicitHeight: navLayout.implicitHeight + navLayout.anchors.margins * 2

    StateLayer {
        onClicked: {
            root.clicked();
            root.navigate();
        }
    }

    RowLayout {
        id: navLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        MaterialIcon {
            id: icon

            visible: text.length > 0
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: label

                Layout.fillWidth: true
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                id: status

                Layout.fillWidth: true
                visible: text.length > 0
                color: Colours.palette.m3onSurfaceVariant
                font: NexusStyle.secondaryFont
                elide: Text.ElideRight
                animate: true
            }
        }

        MaterialIcon {
            id: trailingIcon

            text: root.trailingIcon
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }
    }
}
