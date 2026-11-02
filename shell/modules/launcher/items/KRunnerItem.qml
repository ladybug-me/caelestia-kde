pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData
    required property var list

    readonly property real iconSize: (Tokens.sizes.launcher.itemHeight - Tokens.padding.small * 2) * 0.8

    /// KRunner sends an empty icon for executables with no themed icon — most shell
    /// scripts and local binaries — and can send a bare path rather than a name.
    /// Both used to reach the icon provider unresolved, which draws its placeholder.
    readonly property string fallbackIcon: {
        const id = root.modelData?.id ?? "";
        if (id.startsWith("exec://"))
            return "application-x-executable";
        if (id.startsWith("file:") || id.includes("_places_"))
            return "inode-directory";
        return "image-missing";
    }

    readonly property string iconSource: {
        const raw = (root.modelData?.icon ?? "").trim();
        if (!raw)
            return Quickshell.iconPath(root.fallbackIcon, "image-missing");
        if (raw.startsWith("file://") || raw.startsWith("image://"))
            return raw;
        if (raw.startsWith("/"))
            return `file://${raw}`;
        return Quickshell.iconPath(raw, root.fallbackIcon);
    }

    function activate(): void {
        if (!root.modelData)
            return;
        root.list.visibilities.launcher = false;
        // The launcher adds this row itself when the query is something to look up
        // rather than something installed, so it carries a url instead of a match id.
        if (root.modelData.webSearchUrl)
            Qt.openUrlExternally(root.modelData.webSearchUrl);
        else
            Search.run(root.modelData.id, "");
    }

    implicitHeight: Tokens.sizes.launcher.itemHeight
    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: root.activate()
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        IconImage {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            implicitSize: root.iconSize
            source: root.iconSource
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: icon.verticalCenter

            implicitHeight: text.implicitHeight + subtext.implicitHeight

            StyledText {
                id: text

                width: parent.width
                text: root.modelData?.text ?? ""
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                id: subtext

                anchors.top: text.bottom
                width: parent.width
                text: (root.modelData?.subtext ?? "").replace(/\s+/g, " ").trim()
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }
    }
}
