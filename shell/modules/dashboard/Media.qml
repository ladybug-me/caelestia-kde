pragma ComponentBehavior: Bound

import "media"
import QtQuick
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities

    property bool initiated: false

    implicitWidth: Tokens.sizes.dashboard.mediaTabWidth
    implicitHeight: Tokens.sizes.dashboard.mediaTabHeight

    Component.onCompleted: Qt.callLater(() => root.initiated = true)

    AmbientGlow {
        anchors.fill: parent
        source: Players.active ? Players.getArtUrl(Players.active) : ""
        active: Config.dashboard.ambientColor && !Colours.light
        glowOpacity: Config.dashboard.ambientOpacity
        useFallback: false
        radius: Tokens.rounding.large
        clip: true
        z: -1
    }

    BackgroundShapes {
        anchors.fill: parent
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.extraLarge

        CoverVisualiser {
            Layout.fillHeight: true
            implicitWidth: Tokens.sizes.dashboard.mediaSectionWidth
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            state: {
                if (!Players.active)
                    return "noMedia";
                if (!root.initiated)
                    return "init";
                return "";
            }

            states: [
                State {
                    name: "init"

                    PropertyChanges {
                        noMedia.opacity: 0
                        content.opacity: 0
                    }
                },
                State {
                    name: "noMedia"

                    PropertyChanges {
                        noMedia.opacity: 1
                        content.opacity: 0
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "init"
                    to: ""

                    Anim {
                        target: content
                        property: "opacity"
                        type: Anim.SlowEffects
                    }
                },
                Transition {
                    from: ""

                    SequentialAnimation {
                        Anim {
                            target: content
                            property: "opacity"
                            type: Anim.DefaultEffects
                        }
                        Anim {
                            target: noMedia
                            property: "opacity"
                            type: Anim.SlowEffects
                        }
                    }
                },
                Transition {
                    to: ""

                    SequentialAnimation {
                        Anim {
                            target: noMedia
                            property: "opacity"
                            type: Anim.DefaultEffects
                        }
                        Anim {
                            target: content
                            property: "opacity"
                            type: Anim.SlowEffects
                        }
                    }
                }
            ]

            Loader {
                id: noMedia

                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -Tokens.padding.extraLarge * 2
                asynchronous: true
                active: opacity > 0
                opacity: 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.small

                    MaterialShape {
                        Layout.topMargin: (pathBounds().height - implicitSize) / 2
                        Layout.bottomMargin: (pathBounds().height - implicitSize) / 2 + Tokens.spacing.small
                        Layout.alignment: Qt.AlignHCenter
                        color: Colours.palette.m3primaryContainer
                        implicitSize: icon.implicitHeight + Tokens.padding.extraLarge * 2
                        shape: MaterialShape.ClamShell

                        Behavior on color {
                            CAnim {}
                        }

                        MaterialIcon {
                            id: icon

                            anchors.centerIn: parent
                            text: "queue_music"
                            fontStyle: Tokens.font.icon.builders.large.scale(2).build()
                            color: Colours.palette.m3onPrimaryContainer
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Nothing playing")
                        font: Tokens.font.headline.medium
                    }

                    StyledText {
                        text: qsTr("Play something for it to show up here!")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }
            }

            Loader {
                id: content

                anchors.fill: parent
                active: Players.active || opacity > 0

                sourceComponent: RowLayout {
                    spacing: Tokens.spacing.extraLarge

                    Details {
                        Layout.fillWidth: true
                    }

                    LyricsAndSelector {
                        Layout.fillHeight: true
                        implicitWidth: Tokens.sizes.dashboard.mediaSectionWidth
                    }
                }
            }
        }
    }
}
