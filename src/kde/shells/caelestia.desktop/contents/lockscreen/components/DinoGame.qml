/*
    SPDX-FileCopyrightText: 2024 ladybug-me
    SPDX-License-Identifier: GPL-3.0-or-later

    DinoGame.qml - lockscreen port of shell/modules/sidebar/DinoGame.qml, using the
    DinoGameBackend singleton from Caelestia.Services. Assets are under ../assets/;
    the sidebar's Quickshell/qs.* imports are plain QtQuick equivalents here.
*/

import QtQuick
import ".."
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Caelestia.Services

Item {
    id: root

    // Color theme, wired from NotifDock palette props.
    property color activeColor: "#a2adac"
    property color bgColor:     "transparent"
    property bool isCaelestiaMode: false


    readonly property bool isPlaying:  DinoGameBackend.isPlaying
    readonly property bool isGameOver: DinoGameBackend.isGameOver

    // Asset root relative to this QML file
    readonly property string assets: Qt.resolvedUrl("../assets/").toString()
    function a(name) { return assets + name; }

    implicitHeight: 200
    clip: true

    onWidthChanged: DinoGameBackend.width = width
    Component.onCompleted: DinoGameBackend.width = width

    // Day/night background
    Rectangle {
        anchors.fill: parent
        color: root.bgColor
        z: -1
        Behavior on color { ColorAnimation { duration: 500 } }
    }

    // Scrolling ground, shown while playing or after a loss
    Item {
        visible: root.isPlaying || root.isGameOver
        width: parent.width
        height: 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        clip: true

        Image {
            x: -DinoGameBackend.groundX
            width: 2400; height: 24
            source: root.a("dino_ground.png")
            fillMode: Image.PreserveAspectFit
            opacity: 0.7
            layer.enabled: true
            layer.effect: ColorOverlay { color: root.activeColor }
        }
        Image {
            x: 2400 - DinoGameBackend.groundX
            width: 2400; height: 24
            source: root.a("dino_ground.png")
            fillMode: Image.PreserveAspectFit
            opacity: 0.7
            layer.enabled: true
            layer.effect: ColorOverlay { color: root.activeColor }
        }
    }

    // Idle scene
    ColumnLayout {
        id: idleScene
        anchors.centerIn: parent

        // Start hidden so the Behavior catches the change on startup
        property bool show: false
        opacity: show ? 1 : 0
        visible: opacity > 0
        // Use a slight vertical shift for a slide-up effect
        transform: Translate { y: idleScene.show ? 0 : 20; Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } } }

        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        // Kick off the initial animation.
        Component.onCompleted: {
            Qt.callLater(function() {
                show = Qt.binding(function() { return !root.isPlaying && !root.isGameOver; });
            });
        }

        spacing: 16

        Item {
            Layout.alignment: Qt.AlignHCenter
            width: 200; height: 87.5

            Image {
                anchors.centerIn: parent
                width: 200; height: 87.5
                source: root.a("dino.png")
                fillMode: Image.PreserveAspectFit
                opacity: root.isCaelestiaMode ? 0 : 0.65
                Behavior on opacity { NumberAnimation { duration: 200 } }
        layer.enabled: !root.isCaelestiaMode
        layer.effect: ColorOverlay { color: root.activeColor }
            }

            Item {
                anchors.centerIn: parent
                width: 200; height: 87.5
                opacity: root.isCaelestiaMode ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Item {
                    anchors.fill: parent
                    clip: true

                    Image {
                        x: 0; y: 68
                        width: 200; height: 19
                        source: root.a("dino_ground.png")
                        fillMode: Image.Pad
                        horizontalAlignment: Image.AlignLeft
                        verticalAlignment: Image.AlignTop
                        opacity: 0.65
        layer.enabled: true
        layer.effect: ColorOverlay { color: root.activeColor }
                    }

                    Image {
                        x: 104; y: 16
                        width: 37; height: 11
                        source: root.a("dino_cloud.png")
                        fillMode: Image.PreserveAspectFit
                        opacity: 0.65
        layer.enabled: true
        layer.effect: ColorOverlay { color: root.activeColor }
                    }

                    Image {
                        x: 32; y: 32
                        width: 37; height: 11
                        source: root.a("dino_cloud.png")
                        fillMode: Image.PreserveAspectFit
                        opacity: 0.65
        layer.enabled: true
        layer.effect: ColorOverlay { color: root.activeColor }
                    }

                    Image {
                        x: 8; y: 34
                        width: 44; height: 38
                        source: root.a("kurukuru_stand.png")
                        fillMode: Image.PreserveAspectFit
                        opacity: 0.85
                    }

                    Image {
                        x: 156; y: 35
                        width: 20; height: 40
                        source: root.a("cactus_large.png")
                        fillMode: Image.PreserveAspectFit
                        opacity: 0.85
        layer.enabled: true
        layer.effect: ColorOverlay { color: root.activeColor }
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "All up to date!"
            font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody; weight: Font.Medium }
            color: root.activeColor
            opacity: 0.8
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Click or press Space to play"
            font { pixelSize: LockScreenConfig.sizeVerySmall; family: LockScreenConfig.fontBody }
            color: root.activeColor
            opacity: 0.5
        }
    }

    // Active game scene
    Item {
        anchors.fill: parent
        visible: root.isPlaying || root.isGameOver

        // Clouds
        Repeater {
            model: DinoGameBackend.clouds
            Image {
                x: modelData.x; y: modelData.y
                width: 92; height: 27
                source: root.a("dino_cloud.png")
                fillMode: Image.PreserveAspectFit
                opacity: 0.5
        layer.enabled: true
        layer.effect: ColorOverlay { color: root.activeColor }
            }
        }

        // Dino character
        Image {
            id: dino
            width:  DinoGameBackend.isDucking ? 59 : 44
            height: DinoGameBackend.isDucking ? 30 : 47
            source: {
                var prefix = root.isCaelestiaMode ? "kurukuru" : "dino";
                if (DinoGameBackend.isGameOver)
                    return root.a(prefix + (root.isCaelestiaMode ? "_stand.png" : "_crash.png"));
                if (DinoGameBackend.dinoY < 0)
                    return root.a(prefix + "_stand.png");
                if (DinoGameBackend.isDucking)
                    return Math.floor(DinoGameBackend.frameCount / 5) % 2 === 0
                           ? root.a(prefix + "_duck1.png") : root.a(prefix + "_duck2.png");
                return Math.floor(DinoGameBackend.frameCount / 5) % 2 === 0
                       ? root.a(prefix + "_run1.png") : root.a(prefix + "_run2.png");
            }
            x: 30
            y: parent.height - 30 - height + DinoGameBackend.dinoY
            opacity: 0.85
        layer.enabled: !root.isCaelestiaMode
        layer.effect: ColorOverlay { color: root.activeColor }
        }

        // Score
        Text {
            text: "HI " + ("00000" + Math.floor(DinoGameBackend.highScore)).slice(-5)
                + "  "  + ("00000" + Math.floor(DinoGameBackend.score)).slice(-5)
            anchors.top:    parent.top
            anchors.right:  parent.right
            anchors.margins: 10
            font { pixelSize: LockScreenConfig.sizeVerySmall; family: LockScreenConfig.fontMono }
            color: root.activeColor
            opacity: 0.8
        }

        // Obstacles
        Repeater {
            model: DinoGameBackend.obstacles
            Image {
                width:  modelData.width
                height: modelData.height
                source: {
                    if (modelData.type === "bird")
                        return Math.floor(DinoGameBackend.frameCount / 7) % 2 === 0
                               ? root.a("bird_1.png") : root.a("bird_2.png");
                    return modelData.type === "small"
                           ? root.a("cactus_small.png") : root.a("cactus_large.png");
                }
                x: modelData.x
                y: parent.height - 30 - height - (modelData.yOffset || 0)
                opacity: 0.85
        layer.enabled: true
        layer.effect: ColorOverlay { color: root.activeColor }
            }
        }

        // Game over overlay
        Column {
            visible: root.isGameOver && Math.floor(DinoGameBackend.score) < 99999
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -30
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "G A M E   O V E R"
                font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody; weight: Font.Medium }
                color: root.activeColor
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Click to restart"
                font { pixelSize: LockScreenConfig.sizeVerySmall; family: LockScreenConfig.fontBody }
                color: root.activeColor
                opacity: 0.6
            }
        }

        // Win overlay
        Column {
            visible: root.isGameOver && Math.floor(DinoGameBackend.score) >= 99999
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -30
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Y O U   W I N !"
                font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody; weight: Font.Medium }
                color: root.activeColor
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Now go touch grass"
                font { pixelSize: LockScreenConfig.sizeVerySmall; family: LockScreenConfig.fontBody }
                color: root.activeColor
                opacity: 0.6
            }
        }
    }

    // Input
    MouseArea {
        anchors.fill: parent
        onClicked: {
            DinoGameBackend.jump();
        }
    }
}
