pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

// A glyph and a label that run a shell command. The whole card is the button, so a
// small one is still easy to hit.
Item {
    id: root

    property var frame
    property var controller

    readonly property var cfg: frame?.config ?? ({})
    readonly property string glyph: cfg.glyph ?? ""
    readonly property string text: cfg.label ?? ""
    readonly property string command: cfg.command ?? ""
    readonly property bool small: Math.min(root.width, root.height) < 64

    function run(): void {
        const line = root.command.trim();
        if (line !== "")
            Launch.exec(["sh", "-c", line]);
    }

    StateLayer {
        anchors.fill: parent
        radius: Tokens.rounding.medium
        onClicked: root.run()
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(root.width - Tokens.padding.small, Math.max(implicitWidth, 0))
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            visible: root.glyph !== ""
            text: root.glyph
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.builders.large.build()
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.text !== "" && !root.small
            text: root.text
            color: Colours.palette.m3onSurface
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    // An empty command looks like a working button that does nothing, so say so.
    MaterialIcon {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.extraSmall
        visible: root.command.trim() === ""
        text: "help"
        color: Colours.palette.m3outline
        fontStyle: Tokens.font.icon.small
    }
}
