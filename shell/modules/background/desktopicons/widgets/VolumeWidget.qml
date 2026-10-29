pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// The default sink or source: a glyph that fills up with the level, the percentage
// beside it, and the device it belongs to. Click the glyph to mute, scroll to change.
Item {
    id: root

    property var frame
    property var controller

    readonly property var cfg: frame?.config ?? ({})
    readonly property bool input: cfg.device === "input"
    readonly property bool showDevice: cfg.showDevice !== false

    readonly property real level: Math.max(0, root.input ? Audio.sourceVolume : Audio.volume)
    readonly property bool muted: root.input ? Audio.sourceMuted : Audio.muted
    readonly property int percent: Math.max(0, Math.round(root.level * 100))
    readonly property string deviceName: {
        const node = root.input ? Audio.source : Audio.sink;
        return node ? Audio.getNodeDisplayName(node) : "";
    }
    readonly property string status: root.muted ? qsTr("Muted") : root.input ? qsTr("Microphone") : qsTr("Volume")
    readonly property string glyph: {
        if (root.muted)
            return root.input ? "mic_off" : "volume_off";
        if (root.input)
            return "mic";
        return root.percent >= 50 ? "volume_up" : "volume_down";
    }
    readonly property real filled: root.muted ? 0 : Math.min(1, root.level)
    readonly property int glyphPoints: Math.max(14, Math.round(Math.min(root.height * 0.44, root.width * 0.4)))

    function toggleMute(): void {
        const node = root.input ? Audio.source : Audio.sink;
        if (node?.audio)
            node.audio.muted = !node.audio.muted;
    }

    function step(up: bool): void {
        if (root.input) {
            if (up)
                Audio.incrementSourceVolume();
            else
                Audio.decrementSourceVolume();
        } else if (up) {
            Audio.incrementVolume();
        } else {
            Audio.decrementVolume();
        }
    }

    WheelHandler {
        acceptedModifiers: Qt.NoModifier
        onWheel: event => {
            if (event.angleDelta.y !== 0)
                root.step(event.angleDelta.y > 0);
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.medium

        Item {
            id: glyphBox

            readonly property real side: Math.min(root.height, root.width * 0.42)

            Layout.preferredWidth: glyphBox.side
            Layout.preferredHeight: glyphBox.side
            Layout.alignment: Qt.AlignVCenter

            MaterialIcon {
                id: track

                anchors.centerIn: parent
                opacity: 0.28
                text: root.glyph
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.size(root.glyphPoints).build()
            }

            // The same glyph again, in the accent colour, clipped bottom-up to the
            // level: the part above the clip is the part that is not filled.
            Item {
                anchors.left: track.left
                anchors.right: track.right
                anchors.bottom: track.bottom
                height: track.height * root.filled
                clip: true

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: root.glyph
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.size(root.glyphPoints).build()
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: Tokens.rounding.full
                onClicked: root.toggleMute()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                Layout.fillHeight: true
            }

            StyledText {
                Layout.fillWidth: true
                text: `${root.percent}%`
                color: root.muted ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                font: Tokens.font.headline.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.status
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.showDevice && root.deviceName !== ""
                text: root.deviceName
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
