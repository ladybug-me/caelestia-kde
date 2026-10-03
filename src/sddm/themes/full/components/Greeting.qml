pragma ComponentBehavior: Bound
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Window

Item {
    id: root

    property bool firstInput
    property bool blurEnabled
    property real mainCardRadius
    property real blurAmount
    property int rootHeight
    property int rootWidth
    property string greetingText
    property string username
    property var videoSourceItem: null
    readonly property var fontAxes: ({
            "wght": 700,
            "wdth": 115,
            "ROND": 10,
            "opsz": 224
        })
    readonly property real screenAvailableWidth: Math.max(1, Math.min(Screen.width > 0 ? Screen.width : 1e9, root.rootWidth > 0 ? root.rootWidth : 1e9) - 120)
    readonly property real fitPointSize: Math.min(80, 80 * screenAvailableWidth / Math.max(1, widthProbe.width))

    FontLoader {
        id: googleSansFlex

        source: "../assets/google-sans-flex/GoogleSansFlex.ttf"
    }

    Text {
        id: widthProbe

        visible: false
        text: root.greetingText + " " + root.username
        font.pointSize: 80
        font.family: googleSansFlex.name
        font.variableAxes: root.fontAxes
        font.features: ({
                "liga": 0
            })
    }

    Rectangle {
        id: welcomeTextRectBlur

        width: root.firstInput ? welcomeTextRect.width + 30 : welcomeTextRect.width / 10
        height: root.firstInput ? welcomeTextRect.height + 30 : welcomeTextRect.height / 10
        color: "transparent"
        anchors.centerIn: parent
        radius: root.mainCardRadius
        clip: true
        layer.enabled: true

        AnimatedImage {
            id: backgroundBlur

            anchors.centerIn: parent
            width: root.rootWidth
            height: root.rootHeight
            source: "../assets/background"
            fillMode: Image.PreserveAspectCrop
            opacity: root.firstInput ? 1 : 0

            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: root.videoSourceItem
                visible: root.videoSourceItem !== null
            }
        }

        MultiEffect {
            blurEnabled: root.blurEnabled
            source: backgroundBlur
            blur: root.blurAmount
            autoPaddingEnabled: false
            blurMultiplier: 1
            blurMax: 64
            anchors.fill: backgroundBlur
            opacity: root.firstInput ? 1 : 0

            Behavior on blur {
                NumberAnimation {
                    duration: 400
                    easing: Easing.InOutCubic
                }
            }
        }

        Rectangle {
            anchors.fill: backgroundBlur
            color: Qt.rgba(parseInt(config.background.substring(1, 3), 16) / 255, parseInt(config.background.substring(3, 5), 16) / 255, parseInt(config.background.substring(5, 7), 16) / 255, 1)
            opacity: root.firstInput ? parseFloat(config.welcomeColorOpacity) : 0
        }

        Behavior on width {
            NumberAnimation {
                duration: 600
                easing.type: Easing.OutBack
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: 600
                easing.type: Easing.OutBack
            }
        }

        layer.effect: OpacityMask {

            maskSource: Rectangle {
                width: welcomeTextRectBlur.width
                height: welcomeTextRectBlur.height
                radius: welcomeTextRectBlur.radius
            }
        }
    }

    Item {
        id: welcomeTextRect

        width: welcomeText.width + 50
        height: welcomeText.height + 30
        anchors.centerIn: parent
        opacity: 1

        Text {
            id: welcomeText

            renderType: Text.QtRendering
            text: "<span style='color:" + config.text + ";'>" + root.greetingText + " " + "</span>" + "<span style='color:" + config.primary + ";'>" + root.username + "</span>"
            textFormat: Text.RichText
            font.pointSize: root.fitPointSize
            font.family: googleSansFlex.name
            font.variableAxes: root.fontAxes
            font.features: ({
                    "liga": 0
                })
            color: config.text
            opacity: root.firstInput ? 1 : 0
            anchors.centerIn: parent
        }

        PropertyAnimation {
            target: welcomeTextRect
            property: "scale"
            from: 0.1
            to: 1
            duration: 600
            easing.type: Easing.OutBack
            running: root.firstInput ? true : false
        }
    }
}
