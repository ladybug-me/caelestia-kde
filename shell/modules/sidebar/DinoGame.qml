import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    property color activeColor: DinoGameBackend.isInverted ? Colours.palette.m3inverseOnSurface : Colours.palette.m3onSurface
    property color bgColor: DinoGameBackend.isInverted ? Colours.palette.m3inverseSurface : "transparent"

    Behavior on activeColor { CAnim {} }
    Behavior on bgColor { CAnim {} }

    property bool isPlaying: DinoGameBackend.isPlaying

    property bool isGameOver: DinoGameBackend.isGameOver

    readonly property bool isRunning: isPlaying && !DinoGameBackend.isPaused

    // The game loop is continuous motion, so the animations switch turns the game off too.
    readonly property bool playable: Tokens.anim.enabled

    implicitWidth: Math.max(250, parent.width * 0.8)

    implicitHeight: 200

    clip: true

    focus: true

    onWidthChanged: DinoGameBackend.width = width

    Component.onCompleted: DinoGameBackend.width = width

    onIsRunningChanged: Notifs.setDndHold("game", isRunning)

    // The backend outlives this item, so a game left behind (sidebar closed or hidden)
    // pauses instead of running blind and holding do-not-disturb until it crashes.
    onVisibleChanged: {
        if (!visible)
            DinoGameBackend.pause();
    }

    onPlayableChanged: {
        if (!playable)
            DinoGameBackend.pause();
    }

    Component.onDestruction: {
        DinoGameBackend.pause();
        Notifs.setDndHold("game", false);
    }

    FrameAnimation {
        running: root.isRunning && root.visible && root.playable
        onTriggered: DinoGameBackend.advance(frameTime * 1000)
    }

    // A Shortcut covers the whole drawers window, and it takes Up before a focused field's
    // Keys handler sees it (the launcher search loses its list navigation). Only while
    // playing or focused, then.
    Shortcut {
        enabled: root.playable && (root.isRunning || root.activeFocus)
        sequence: "Space"
        onActivated: {
            root.forceActiveFocus();
            DinoGameBackend.jump();
        }
    }
    Shortcut {
        enabled: root.playable && (root.isRunning || root.activeFocus)
        sequence: "Up"
        onActivated: {
            root.forceActiveFocus();
            DinoGameBackend.jump();
        }
    }

    Keys.onDownPressed: (event) => {
        if (event.isAutoRepeat) return;
        if (root.isPlaying) DinoGameBackend.isDucking = true;
    }

    Keys.onReleased: (event) => {
        if (event.isAutoRepeat) return;
        if (event.key === Qt.Key_Down) DinoGameBackend.isDucking = false;
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.playable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            // so Down can duck after a game started with the mouse
            root.forceActiveFocus();
            DinoGameBackend.jump()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.bgColor
        z: -1
    }

    Item {
        visible: root.isPlaying || root.isGameOver
        width: parent.width
        height: 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        clip: true

        Image {
            x: -DinoGameBackend.groundX
            width: 2400
            height: 24
            source: Paths.absolutePath("root:/assets/dino_ground.png")
            fillMode: Image.PreserveAspectFit

            layer.enabled: true
            layer.effect: Colouriser {
                colorizationColor: root.activeColor
                brightness: 1
            }
        }

        Image {
            x: 2400 - DinoGameBackend.groundX
            width: 2400
            height: 24
            source: Paths.absolutePath("root:/assets/dino_ground.png")
            fillMode: Image.PreserveAspectFit

            layer.enabled: true
            layer.effect: Colouriser {
                colorizationColor: root.activeColor
                brightness: 1
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.isPlaying && !root.isGameOver
        spacing: Tokens.spacing.extraLarge

        Item {
            Layout.alignment: Qt.AlignHCenter
            width: 250
            height: 109.375

            Image {
                anchors.centerIn: parent
                width: 250
                height: 109.375
                source: Paths.absolutePath(Config.paths.noNotifsPic)
                fillMode: Image.PreserveAspectFit
                opacity: GlobalConfig.general.caelestiaMode ? 0 : 1

                Behavior on opacity { Anim { type: Anim.Standard } }

                layer.enabled: true

                layer.effect: Colouriser {
                    colorizationColor: root.activeColor
                    brightness: 1
                }
            }

            Item {
                anchors.centerIn: parent
                width: 250
                height: 109.375
                opacity: GlobalConfig.general.caelestiaMode ? 1 : 0

                Behavior on opacity { Anim { type: Anim.Standard } }

                Item {
                    anchors.fill: parent
                    clip: true

                    Image {
                        x: 0
                        y: 86
                        width: 250
                        height: 24
                        source: Paths.absolutePath("root:/assets/dino_ground.png")
                        fillMode: Image.Pad
                        horizontalAlignment: Image.AlignLeft
                        verticalAlignment: Image.AlignTop

                        layer.enabled: true
                        layer.effect: Colouriser {
                            colorizationColor: root.activeColor
                            brightness: 1
                        }
                    }

                    Image {
                        x: 130
                        y: 20
                        width: 46
                        height: 13.5
                        source: Paths.absolutePath("root:/assets/dino_cloud.png")
                        fillMode: Image.PreserveAspectFit

                        layer.enabled: true
                        layer.effect: Colouriser {
                            colorizationColor: root.activeColor
                            brightness: 1
                        }
                    }

                    Image {
                        x: 40
                        y: 40
                        width: 46
                        height: 13.5
                        source: Paths.absolutePath("root:/assets/dino_cloud.png")
                        fillMode: Image.PreserveAspectFit

                        layer.enabled: true
                        layer.effect: Colouriser {
                            colorizationColor: root.activeColor
                            brightness: 1
                        }
                    }

                    Image {
                        x: 10
                        y: 43
                        width: 55
                        height: 47
                        source: Paths.absolutePath("root:/assets/kurukuru_stand.png")
                        fillMode: Image.PreserveAspectFit
                    }

                    Image {
                        x: 195
                        y: 44
                        width: 25
                        height: 50
                        source: Paths.absolutePath("root:/assets/cactus_large.png")
                        fillMode: Image.PreserveAspectFit

                        layer.enabled: true
                        layer.effect: Colouriser {
                            colorizationColor: root.activeColor
                            sourceColor: "white"
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("All up to date!")
            color: root.activeColor
            font: Tokens.font.headline.builders.small.width(90).build()
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: root.playable
            text: qsTr("Click to play")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
        }
    }

    Item {
        anchors.fill: parent
        visible: root.isPlaying || root.isGameOver

        // Indexed by count: the backend hands out a new list every frame, and a list model
        // would rebuild every delegate, layer and shader 60 times a second.
        Repeater {
            model: DinoGameBackend.clouds.length

            Image {
                required property int index
                readonly property var cloud: DinoGameBackend.clouds[index] ?? ({})

                x: cloud.x ?? 0
                y: cloud.y ?? 0
                width: 92
                height: 27
                source: Paths.absolutePath("root:/assets/dino_cloud.png")
                fillMode: Image.PreserveAspectFit

                layer.enabled: true
                layer.effect: Colouriser {
                    colorizationColor: root.activeColor
                    brightness: 1
                }
            }
        }

        Image {
            id: dino

            width: DinoGameBackend.isDucking ? 59 : 44
            height: DinoGameBackend.isDucking ? 30 : 47
            source: {
                var prefix = GlobalConfig.general.caelestiaMode ? "kurukuru" : "dino";
                if (DinoGameBackend.isGameOver) return Paths.absolutePath("root:/assets/" + prefix + (GlobalConfig.general.caelestiaMode ? "_stand.png" : "_crash.png"));
                if (DinoGameBackend.dinoY < 0) return Paths.absolutePath("root:/assets/" + prefix + "_stand.png");
                if (DinoGameBackend.isDucking) return Math.floor(DinoGameBackend.frameCount / 5) % 2 === 0 ? Paths.absolutePath("root:/assets/" + prefix + "_duck1.png") : Paths.absolutePath("root:/assets/" + prefix + "_duck2.png");
                return Math.floor(DinoGameBackend.frameCount / 5) % 2 === 0 ? Paths.absolutePath("root:/assets/" + prefix + "_run1.png") : Paths.absolutePath("root:/assets/" + prefix + "_run2.png");
            }
            x: 30
            y: parent.height - 30 - height + DinoGameBackend.dinoY

            layer.enabled: !GlobalConfig.general.caelestiaMode
            layer.effect: Colouriser {
                colorizationColor: root.activeColor
                sourceColor: "white"
            }
        }

        StyledText {
            text: "HI " + ("00000" + Math.floor(DinoGameBackend.highScore)).slice(-5) + "  " + ("00000" + Math.floor(DinoGameBackend.score)).slice(-5)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            font: Tokens.font.label.large
            color: root.activeColor
            Component.onCompleted: font.features = {"tnum": 1}
        }

        Repeater {
            model: DinoGameBackend.obstacles.length

            Image {
                required property int index
                readonly property var obstacle: DinoGameBackend.obstacles[index] ?? ({})

                width: obstacle.width ?? 0
                height: obstacle.height ?? 0
                source: {
                    if (obstacle.type === "bird") return Math.floor(DinoGameBackend.frameCount / 7) % 2 === 0 ? Paths.absolutePath("root:/assets/bird_1.png") : Paths.absolutePath("root:/assets/bird_2.png");
                    return obstacle.type === "small" ? Paths.absolutePath("root:/assets/cactus_small.png") : Paths.absolutePath("root:/assets/cactus_large.png");
                }
                x: obstacle.x ?? 0
                y: parent.height - 30 - height - (obstacle.yOffset || 0)

                layer.enabled: true
                layer.effect: Colouriser {
                    colorizationColor: root.activeColor
                    sourceColor: "white"
                }
            }
        }
    }

    StyledText {
        id: gameOverText

        visible: root.isGameOver && Math.floor(DinoGameBackend.score) < 99999
        text: qsTr("G A M E   O V E R\nClick to restart")
        horizontalAlignment: Text.AlignHCenter
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        font: Tokens.font.title.large
        color: root.activeColor
    }

    StyledText {
        visible: root.isGameOver && Math.floor(DinoGameBackend.score) >= 99999
        text: qsTr("Y O U   W I N !\nNow go touch grass")
        horizontalAlignment: Text.AlignHCenter
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        font: Tokens.font.title.large
        color: root.activeColor
    }

    StyledText {
        visible: gameOverText.visible && DinoGameBackend.isNewHighScore
        text: qsTr("New high score: %1").arg(Math.floor(DinoGameBackend.highScore))
        anchors.top: gameOverText.bottom
        anchors.topMargin: Tokens.spacing.small
        anchors.horizontalCenter: parent.horizontalCenter
        font: Tokens.font.label.large
        color: root.activeColor
        Component.onCompleted: font.features = {"tnum": 1}
    }

    StyledText {
        visible: root.isPlaying && DinoGameBackend.isPaused
        text: qsTr("P A U S E D\nClick to continue")
        horizontalAlignment: Text.AlignHCenter
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        font: Tokens.font.title.large
        color: root.activeColor
    }
}
