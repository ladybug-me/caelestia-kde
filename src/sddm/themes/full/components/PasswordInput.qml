pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "shapes"
import "shapes/material-shapes.js" as MaterialShapes
import "shapes/shapes/morph.js" as Morph

Rectangle {
    id: passwordRoot
    color: "transparent"

    property alias sessionIndex: inputRect.sessionIndex
    property alias currentUser: inputRect.currentUser
    property alias buffer: inputRect.buffer

    onBufferChanged: {
        while (dotModel.count < buffer.length)
            dotModel.append({
                shapeIdx: Math.floor(Math.random() * 5)
            });
        while (dotModel.count > buffer.length)
            dotModel.remove(dotModel.count - 1);
    }

    ListModel {
        id: dotModel
    }

    function dotPath(morph, progress, size) {
        const cubics = morph.asCubics(progress);
        if (!cubics || cubics.length === 0)
            return "";
        let d = "M " + (cubics[0].anchor0X * size) + " " + (cubics[0].anchor0Y * size);
        for (const c of cubics)
            d += " C " + (c.control0X * size) + " " + (c.control0Y * size) + " " + (c.control1X * size) + " " + (c.control1Y * size) + " " + (c.anchor1X * size) + " " + (c.anchor1Y * size);
        return d + " Z";
    }

    property alias isLoading: inputRect.isLoading
    property alias firstInput: inputRect.firstInput
    property alias mainCardComponentsOpacity: inputRect.mainCardComponentsOpacity

    function shake() {
        inputRect.shake();
    }

    Rectangle {
        id: inputRect

        property real mainCardComponentsOpacity
        property bool firstInput
        property bool isLoading
        property string buffer
        property string currentUser
        property int sessionIndex
        anchors.horizontalCenter: parent.horizontalCenter

        onIsLoadingChanged: {
            if (!inputRect.isLoading) {
                inputRect.width = 365;
            }
        }

        color: config.subComponents
        radius: 30
        width: inputRect.buffer === "" ? 300 : 365
        height: 45
        opacity: inputRect.firstInput ? 0 : inputRect.mainCardComponentsOpacity

        Behavior on width {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutBack
            }
        }

        function shake() {
            shakeRotation.start();
        }

        Text {
            id: lockIcon
            renderType: Text.NativeRendering
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 17
            font.family: "Material Symbols Rounded"
            font.pointSize: 15
            text: "\ue897"
            color: '#a8a8a8'
            visible: !inputRect.isLoading
        }

        ShapeCanvas {
            id: loadingShape
            property int index: 0
            property var shapeGetters: [MaterialShapes.getGem, MaterialShapes.getSunny, MaterialShapes.getCookie4Sided, MaterialShapes.getCookie6Sided, MaterialShapes.getVerySunny]
            opacity: inputRect.isLoading ? 1 : 0
            color: config.secondary

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 17

            implicitWidth: lockIcon.height / 2 * 2.1
            implicitHeight: lockIcon.height / 2 * 2.1
            roundedPolygon: loadingShape.shapeGetters[loadingShape.index]()

            Timer {
                running: inputRect.isLoading
                interval: 500
                onTriggered: {
                    if (loadingShape.index == 4) {
                        loadingShape.index = 0;
                    } else {
                        loadingShape.index = loadingShape.index + 1;
                    }
                    scaleAnim.running = true;
                }
                repeat: true
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 400
                }
            }
        }

        SequentialAnimation {
            id: scaleAnim

            running: false

            NumberAnimation {
                target: loadingShape
                property: "scale"
                to: 1.2
                duration: 100
            }
            NumberAnimation {
                target: loadingShape
                property: "scale"
                to: 1
                duration: 100
            }
        }

        SequentialAnimation {
            id: shakeRotation

            running: false

            NumberAnimation {
                target: inputRect
                property: "rotation"
                to: -6
                duration: 50
            }

            NumberAnimation {
                target: inputRect
                property: "rotation"
                to: 6
                duration: 50
            }

            NumberAnimation {
                target: inputRect
                property: "rotation"
                to: -4
                duration: 50
            }

            NumberAnimation {
                target: inputRect
                property: "rotation"
                to: 4
                duration: 50
            }

            NumberAnimation {
                target: inputRect
                property: "rotation"
                to: -2
                duration: 50
            }

            NumberAnimation {
                target: inputRect
                property: "rotation"
                to: 2
                duration: 50
            }

            NumberAnimation {
                target: inputRect
                property: "rotation"
                to: 0
                duration: 50
            }
        }

        SequentialAnimation {
            id: pulseColorRect1

            running: inputRect.isLoading

            NumberAnimation {
                target: inputRect
                property: "width"
                to: 300
                duration: 300
                easing.type: Easing.OutBack
            }
        }

        Rectangle {
            id: inputBorders

            anchors.centerIn: parent
            color: "transparent"
            radius: 30
            width: 250
            height: 40
            clip: true

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                font.pointSize: 12
                text: inputRect.isLoading ? "Loading..." : "Enter your password"
                color: '#6e6e6e'
                font.family: "Rubik"
                opacity: inputRect.buffer === "" ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 100
                    }
                }
            }

            ListView {
                id: dots

                orientation: ListView.Horizontal
                spacing: 3
                interactive: false

                width: inputRect.buffer.length * 15 + (inputRect.buffer.length - 1) * 3 + parent.height
                height: 15
                anchors.centerIn: parent

                model: dotModel

                Behavior on width {
                    NumberAnimation {
                        duration: 150
                        easing: Easing.OutCubic
                    }
                }

                delegate: Item {
                    id: dot

                    required property int shapeIdx

                    width: 15
                    height: 15
                    scale: 0
                    opacity: 0

                    property var shapeGetters: [MaterialShapes.getGem, MaterialShapes.getSunny, MaterialShapes.getCookie4Sided, MaterialShapes.getVerySunny, MaterialShapes.getCookie6Sided]
                    property var morph: new Morph.Morph(shapeGetters[shapeIdx](), MaterialShapes.getCircle())
                    property real morphProgress: 0

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            fillColor: "white"
                            strokeColor: "transparent"
                            strokeWidth: 0

                            PathSvg {
                                path: passwordRoot.dotPath(dot.morph, dot.morphProgress, Math.min(dot.width, dot.height))
                            }
                        }
                    }

                    SequentialAnimation {
                        id: initAnim
                        running: true

                        ParallelAnimation {
                            NumberAnimation {
                                target: dot
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: 150
                            }
                            SequentialAnimation {
                                NumberAnimation {
                                    target: dot
                                    property: "scale"
                                    from: 0
                                    to: 1.4
                                    duration: 180
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: dot
                                    property: "scale"
                                    to: 1
                                    duration: 150
                                }
                            }
                        }
                        PauseAnimation {
                            duration: 180
                        }
                        NumberAnimation {
                            target: dot
                            property: "morphProgress"
                            from: 0
                            to: 1
                            duration: 350
                            easing.type: Easing.OutCubic
                        }
                    }

                    ListView.onRemove: {
                        initAnim.stop();
                        removeAnim.start();
                    }

                    SequentialAnimation {
                        id: removeAnim

                        PropertyAction {
                            target: dot
                            property: "ListView.delayRemove"
                            value: true
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: dot
                                property: "opacity"
                                to: 0
                                duration: 150
                            }
                            NumberAnimation {
                                target: dot
                                property: "scale"
                                to: 0
                                duration: 150
                                easing.type: Easing.InCubic
                            }
                        }
                        PropertyAction {
                            target: dot
                            property: "ListView.delayRemove"
                            value: false
                        }
                    }
                }
            }
        }

        Rectangle {
            id: inputButtonShape

            radius: 48
            width: inputRect.height - 7
            height: inputRect.height - 7
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 4
            color: "transparent"

            property var shapeGetters: [MaterialShapes.getCircle, MaterialShapes.getArrow]

            ShapeCanvas {
                id: shape
                rotation: 90
                scale: inputRect.buffer === "" ? 0.9 : 0.7
                implicitWidth: inputButtonShape.height / 2 * 2.1
                implicitHeight: inputButtonShape.height / 2 * 2.1
                roundedPolygon: inputRect.buffer === "" ? inputButtonShape.shapeGetters[0]() : inputButtonShape.shapeGetters[1]()
                color: inputRect.buffer === "" ? config.inverseOnSurface : config.secondary
                y: -1

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    font.family: "Material Symbols Rounded"
                    font.pointSize: 24
                    rotation: -90
                    text: "\ue941"
                    color: config.text
                    opacity: inputRect.buffer === "" ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: inputRect.buffer === "" ? false : true
                    onEntered: {
                        shape.scale = 0.8;
                    }
                    onExited: {
                        shape.scale = 0.7;
                    }
                    onClicked: {
                        sddm.login(inputRect.currentUser, inputRect.buffer, inputRect.sessionIndex);
                        inputRect.isLoading = true;
                        inputRect.buffer = "";
                    }
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutBack
            }
        }
    }
}
