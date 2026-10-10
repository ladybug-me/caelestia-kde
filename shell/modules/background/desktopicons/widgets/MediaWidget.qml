pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Now playing from the active MPRIS player, with transport controls.
Item {
    id: root

    property var frame
    property var controller

    readonly property var player: Players.active
    readonly property real progress: player?.length > 0 ? Math.min(1, (player.position % player.length) / player.length) : 0
    readonly property string artUrl: Players.getArtUrl(player)

    Timer {
        running: root.player?.isPlaying ?? false
        interval: 1000
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    StyledText {
        anchors.centerIn: parent
        visible: !root.player
        text: qsTr("Nothing playing")
        color: Colours.palette.m3outline
        font: Tokens.font.body.medium
    }

    RowLayout {
        anchors.fill: parent
        visible: !!root.player
        spacing: Tokens.spacing.large

        StyledClippingRect {
            Layout.fillHeight: true
            Layout.preferredWidth: height
            Layout.maximumWidth: root.width * 0.45
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surfaceContainerHigh

            MaterialIcon {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: "music_note"
                color: Colours.palette.m3outline
                fontStyle: Tokens.font.icon.builders.extraLarge.build()
            }

            Image {
                id: art

                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                retainWhileLoading: true
                sourceSize.width: width
                sourceSize.height: height
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.small

            Item {
                Layout.fillHeight: true
            }

            StyledText {
                Layout.fillWidth: true
                text: root.player?.trackTitle || qsTr("Unknown title")
                font: Tokens.font.title.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.player?.trackArtist || Players.getIdentity(root.player)
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                implicitHeight: 4
                radius: 2
                color: Qt.alpha(Colours.palette.m3onSurface, 0.15)

                StyledRect {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: parent.radius
                    color: Colours.palette.m3primary

                    Behavior on width {
                        Anim {
                            type: Anim.StandardSmall
                        }
                    }
                }

                // Click or drag along the bar to seek.
                MouseArea {
                    function seek(x: real): void {
                        if (root.player?.length > 0)
                            root.player.position = Math.max(0, Math.min(1, x / width)) * root.player.length;
                    }

                    anchors.fill: parent
                    anchors.topMargin: -Tokens.padding.small
                    anchors.bottomMargin: -Tokens.padding.small
                    enabled: root.player?.canSeek ?? false
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => seek(mouse.x)
                    onPositionChanged: mouse => seek(mouse.x)
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.small

                IconButton {
                    type: IconButton.Text
                    icon: "skip_previous"
                    disabled: !root.player?.canGoPrevious
                    onClicked: root.player?.previous()
                }

                IconButton {
                    type: IconButton.Tonal
                    isRound: true
                    icon: root.player?.isPlaying ? "pause" : "play_arrow"
                    disabled: !root.player?.canTogglePlaying
                    onClicked: root.player?.togglePlaying()
                }

                IconButton {
                    type: IconButton.Text
                    icon: "skip_next"
                    disabled: !root.player?.canGoNext
                    onClicked: root.player?.next()
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
