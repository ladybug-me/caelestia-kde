
import QtQuick
import ".."
import QtQuick.Layouts
import QtQuick.Shapes
import M3Shapes
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root

    property int liveCpu: 0
    property int liveTemp: 0
    property int liveRam: 0
    property int liveDisk: 0

    property real cpuPercentage: 0.0
    property real memoryPercentage: 0.0
    property real storagePercentage: 0.0

    property real centerScale: 1.0

    property color clSurface: "#0a0f0f"
    property color clSurfaceContainer: "#131b1a"
    property color clSurfaceContainerHigh: "#192120"
    property color clSurfaceContainerHighest: "#1d2827"
    property color clPrimaryContainer: "#255b58"
    property color clSecondaryContainer: "#27403e"
    property color clTertiary: "#d5efff"
    property color clOnTertiary: "#2e5c72"
    property color clOutline: "#6d7876"
    property color clSurfaceFg: "#dce8e6"
    property color clSurfaceVariantFg: "#a2adac"
    property color clPrimary: "#9bd0cc"
    property color clSecondary: "#b0ccc9"
    property color clError: "#fa746f"

    property real cardRadius: 26
    radius: cardRadius
    color: clSurfaceContainer
    clip: true

    RowLayout {
        anchors.fill: parent
        anchors.margins: Math.max(8, 12 * root.centerScale)
        spacing: Math.max(6, 10 * root.centerScale)

        ResourceItem {
            id: cpu
            Layout.fillWidth: true
            Layout.fillHeight: true
            centerScale: root.centerScale
            icon: "memory"
            value: root.liveCpu + "%"
            shapeType: MaterialShape.Pentagon
            shapeColor: root.clPrimaryContainer
            fillColor: Qt.rgba(root.clSecondary.r, root.clSecondary.g, root.clSecondary.b, 0.3)
            fillPercent: Math.max(0, Math.min(1.0, root.cpuPercentage))
            iconColor: root.clSecondary
            valueColor: root.clPrimary

            MaterialShape {
                id: tempBadge
                readonly property real badgeSize: Math.max(16, Math.round(cpu.shapeSize * 0.32))
                x: cpu.mShape.pointAtAngle(45).x - badgeSize / 2 + Math.max(2, 4 * root.centerScale)
                y: cpu.mShape.pointAtAngle(45).y - badgeSize / 2
                shape: root.liveTemp > 90 ? MaterialShape.SoftBurst : MaterialShape.Circle
                color: root.liveTemp > 90 ? root.clError : root.clSecondaryContainer
                implicitSize: badgeSize

                Text {
                    anchors.centerIn: parent
                    text: root.liveTemp + "°C"
                    font {
                        pixelSize: Math.max(8, Math.round(tempBadge.badgeSize * 0.45))
                        family: LockScreenConfig.fontMetrics
                        weight: Font.Medium
                    }
                    color: root.liveTemp > 90 ? root.clSurface : root.clSecondary
                }
            }
        }

        ResourceItem {
            id: ram
            Layout.fillWidth: true
            Layout.fillHeight: true
            centerScale: root.centerScale
            icon: "memory_alt"
            value: root.liveRam + "%"
            shapeType: MaterialShape.Slanted
            shapeColor: root.clOnTertiary
            fillColor: Qt.rgba(root.clTertiary.r, root.clTertiary.g, root.clTertiary.b, 0.3)
            fillPercent: Math.max(0, Math.min(1.0, root.memoryPercentage))
            iconColor: root.clSecondary
            valueColor: root.clTertiary
        }

        ResourceItem {
            id: disk
            Layout.fillWidth: true
            Layout.fillHeight: true
            centerScale: root.centerScale
            icon: "hard_disk"
            value: root.liveDisk + "%"
            shapeType: MaterialShape.Gem
            shapeColor: root.clSecondaryContainer
            fillColor: Qt.rgba(root.clSecondary.r, root.clSecondary.g, root.clSecondary.b, 0.4)
            fillPercent: Math.max(0, Math.min(1.0, root.storagePercentage))
            iconColor: root.clSecondary
            valueColor: root.clSecondary
        }
    }

    component ResourceItem: Item {
        id: res

        property real centerScale: 1.0
        property string icon: ""
        property string value: ""
        property int shapeType: MaterialShape.Circle
        property color shapeColor: "#192120"
        property color fillColor: "cyan"
        property real fillPercent: 0.0
        property color iconColor: "#b0ccc9"
        property color valueColor: "#dce8e6"

        readonly property real shapeSize: Math.max(1, Math.min(width, height))
        readonly property alias mShape: shape

        MaterialShape {
            id: shape
            anchors.centerIn: parent
            implicitWidth: res.shapeSize
            implicitHeight: res.shapeSize
            implicitSize: res.shapeSize
            shape: res.shapeType
            color: res.shapeColor
        }

        Item {
            anchors.fill: shape
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: shape
            }

            Shape {
                id: wave
                anchors.bottom: parent.bottom
                property real wl: parent.width / 3
                width: parent.width + wl
                height: Math.max(0, Math.min(parent.height, parent.height * res.fillPercent))
                visible: height > 0

                Behavior on height {
                    NumberAnimation { duration: 1000; easing.type: Easing.OutCubic }
                }

                NumberAnimation on x {
                    from: 0
                    to: -wave.wl
                    duration: 1500
                    loops: Animation.Infinite
                    running: wave.visible
                }

                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: res.fillColor

                    PathSvg {
                        path: {
                            const w = wave.width;
                            const h = wave.height;
                            if (w <= 0 || h <= 0) return "";
                            const a = 2.5 * res.centerScale;
                            const n = 4;
                            const wl = wave.wl;
                            const half = wl / 2;

                            let d = `M 0,${a} `;
                            for (let i = 0; i < n; ++i) {
                                const x = i * wl;
                                d += `Q ${x + half / 2},${-a} ${x + half},${a} `;
                                d += `Q ${x + half + half / 2},${3 * a} ${x + wl},${a} `;
                            }
                            d += `L ${w},${h} L 0,${h} Z`;
                            return d;
                        }
                    }
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: res.icon
                font.family: LockScreenConfig.fontIcon
                font.pixelSize: Math.max(14, Math.round(res.shapeSize * 0.32))
                color: res.iconColor
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: res.value
                font {
                    pixelSize: Math.max(11, Math.round(res.shapeSize * 0.23))
                    family: LockScreenConfig.fontMetrics
                    weight: Font.DemiBold
                }
                color: res.valueColor
            }
        }
    }
}
