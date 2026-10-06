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

    Behavior on activeColor { CAnim { duration: 500 } }
    Behavior on bgColor { CAnim { duration: 500 } }
    
    property bool isPlaying: DinoGameBackend.isPlaying

    property bool isGameOver: DinoGameBackend.isGameOver

    property bool _previousDnd: false
    
    implicitWidth: Math.max(250, parent.width * 0.8)

    implicitHeight: 200

    clip: true

    focus: true
    
    onWidthChanged: DinoGameBackend.width = width

    Component.onCompleted: DinoGameBackend.width = width
    
    Connections {
        target: DinoGameBackend

        function onGameStarted() {
            _previousDnd = Notifs.dnd;
            if (!Notifs.dnd) Notifs.dnd = true;
        }

        function onGameDied() {
            if (!_previousDnd) Notifs.dnd = false;
        }
    }
    
    Component.onDestruction: {
        if (isPlaying && !_previousDnd) {
            Notifs.dnd = false;
        }
    }
    
    Shortcut {
        sequence: "Space"
        onActivated: {
            root.forceActiveFocus();
            DinoGameBackend.jump();
        }
    }
    Shortcut {
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
        hoverEnabled: true
        onClicked: {
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
    }
    
    Item {
        anchors.fill: parent
        visible: root.isPlaying || root.isGameOver
        
        Repeater {
            model: DinoGameBackend.clouds

            Image {
                x: modelData.x
                y: modelData.y
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
            model: DinoGameBackend.obstacles

            Image {
                width: modelData.width
                height: modelData.height
                source: {
                    if (modelData.type === "bird") return Math.floor(DinoGameBackend.frameCount / 7) % 2 === 0 ? Paths.absolutePath("root:/assets/bird_1.png") : Paths.absolutePath("root:/assets/bird_2.png");
                    return modelData.type === "small" ? Paths.absolutePath("root:/assets/cactus_small.png") : Paths.absolutePath("root:/assets/cactus_large.png");
                }
                x: modelData.x
                y: parent.height - 30 - height - (modelData.yOffset || 0)
                
                layer.enabled: true
                layer.effect: Colouriser {
                    colorizationColor: root.activeColor
                    sourceColor: "white"
                }
            }
        }
    }
    
    StyledText {
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
}
