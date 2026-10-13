
import QtQuick
import ".."
import QtCore
import M3Shapes
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property string userImage: ""
    property string userName: ""
    property real centerScale: 1.0
    property int profileShape: MaterialShape.Pentagon
    property color clSurfaceContainerHighest: "#1d2827"
    property color clSurfaceVariantFg: "#a2adac"

    readonly property string homeDir: (typeof StandardPaths !== "undefined" && StandardPaths.writableLocation)
        ? StandardPaths.writableLocation(StandardPaths.HomeLocation)
        : (root.userName ? ("file:///home/" + root.userName) : "")
    readonly property string faceSource: homeDir ? (homeDir + "/.face") : ""
    readonly property string fallbackSource: (root.userImage && root.userImage.toString().length > 0)
        ? root.userImage.toString()
        : ""

    property bool rotateShape: false

    readonly property bool isRandomShape: root.profileShape === -1

    readonly property var shapePool: [
        MaterialShape.Circle,
        MaterialShape.Square,
        MaterialShape.Pill,
        MaterialShape.Diamond,
        MaterialShape.ClamShell,
        MaterialShape.Pentagon,
        MaterialShape.Gem,
        MaterialShape.Cookie4Sided,
        MaterialShape.Cookie6Sided,
        MaterialShape.Cookie7Sided,
        MaterialShape.Cookie9Sided,
        MaterialShape.Cookie12Sided,
        MaterialShape.Sunny,
        MaterialShape.SoftBurst
    ]

    property int currentShapeIndex: Math.floor(Math.random() * shapePool.length)
    readonly property int activeShape: isRandomShape ? shapePool[currentShapeIndex] : root.profileShape

    Timer {
        id: shapeAnimTimer
        interval: 3500
        repeat: true
        running: root.isRandomShape && root.visible
        onTriggered: {
            var nextIdx;
            do {
                nextIdx = Math.floor(Math.random() * root.shapePool.length);
            } while (nextIdx === root.currentShapeIndex && root.shapePool.length > 1);
            root.currentShapeIndex = nextIdx;
        }
    }

    Item {
        id: shapeWrapper
        anchors.centerIn: parent
        width: root.width
        height: root.width

        MaterialShape {
            id: shape
            anchors.centerIn: parent
            implicitSize: root.width
            animationDuration: root.isRandomShape ? 800 : 350
            shape: root.activeShape
            color: root.clSurfaceContainerHighest

            NumberAnimation on rotation {
                from: 0
                to: 360
                duration: 12000
                loops: Animation.Infinite
                running: root.rotateShape && root.visible
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: "person"
        font.family: "Material Symbols Rounded"
        font.pixelSize: root.width * 0.4
        color: root.clSurfaceVariantFg
        visible: profileImage.status !== Image.Ready
    }

    Image {
        id: profileImage
        anchors.fill: shapeWrapper
        source: root.faceSource ? root.faceSource : root.fallbackSource
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: shapeWrapper
        }

        onStatusChanged: {
            if (status === Image.Error && source.toString() === root.faceSource.toString() && root.fallbackSource) {
                source = root.fallbackSource;
            }
        }
    }
}
