
import QtQuick
import ".."
import QtQuick.Layouts

ColumnLayout {
    id: root

    property bool use12h: true
    property real centerScale: 1.0

    property color clPrimary: "#9bd0cc"
    property color clSecondary: "#b0ccc9"
    property color clSurfaceContainerHigh: "#192120"
    property color clSurfaceFg: "#dce8e6"
    property color clSurfaceVariantFg: "#a2adac"

    property var currentTime: new Date()

    FontLoader {
        id: gsfFont
        source: "../../fonts/GoogleSansFlex.ttf"
    }

    readonly property string clockFontFamily: gsfFont.status === FontLoader.Ready && gsfFont.name.length > 0 ? gsfFont.name : (gsfFont.name.length > 0 ? gsfFont.name : "Google Sans Flex")

    function calcTopOff(metrics) {
        return metrics.tightBoundingRect.y - metrics.boundingRect.y;
    }

    spacing: Math.max(6, Math.round(10 * root.centerScale))

    Item {
        id: clockDisplay
        Layout.alignment: Qt.AlignHCenter

        implicitWidth: hours.implicitWidth + minutes.implicitWidth + (8 * root.centerScale)
        implicitHeight: hourMetrics.tightBoundingRect.height

        Text {
            id: hours
            y: -root.calcTopOff(hourMetrics)
            text: {
                var h = root.currentTime.getHours();
                if (root.use12h) {
                    h = h % 12;
                    if (h === 0) h = 12;
                }
                return h < 10 ? "0" + h : "" + h;
            }
            color: root.clPrimary
            font {
                family: root.clockFontFamily
                pointSize: Math.max(1, Math.round(72 * root.centerScale))
                weight: Font.Normal
                variableAxes: ({ "wdth": 100 })
            }

            TextMetrics {
                id: hourMetrics
                text: hours.text
                font: hours.font
            }
        }

        Text {
            id: minutes
            anchors.right: parent.right
            y: -root.calcTopOff(minuteMetrics)
            text: {
                var m = root.currentTime.getMinutes();
                return m < 10 ? "0" + m : "" + m;
            }
            color: root.clSecondary
            font {
                family: root.clockFontFamily
                pointSize: Math.max(1, Math.round((root.use12h ? 40 : 72) * root.centerScale))
                weight: Font.Normal
                variableAxes: ({ "wdth": 100 })
            }

            TextMetrics {
                id: minuteMetrics
                text: minutes.text
                font: minutes.font
            }
        }

        Rectangle {
            id: amPmBadge
            anchors.left: minutes.left
            anchors.leftMargin: minuteMetrics.tightBoundingRect.x
            y: hourMetrics.tightBoundingRect.height - implicitHeight
            visible: root.use12h
            color: Qt.rgba(root.clSurfaceContainerHigh.r, root.clSurfaceContainerHigh.g, root.clSurfaceContainerHigh.b, 0.45)
            radius: 12 * root.centerScale

            implicitWidth: minuteMetrics.tightBoundingRect.width
            implicitHeight: amPmMetrics.tightBoundingRect.height + (16 * root.centerScale)

            Text {
                id: amPm
                anchors.centerIn: parent
                width: amPmMetrics.tightBoundingRect.width
                height: amPmMetrics.tightBoundingRect.height
                transform: Translate {
                    x: -amPmMetrics.tightBoundingRect.x
                    y: -root.calcTopOff(amPmMetrics)
                }

                text: root.currentTime.getHours() >= 12 ? "PM" : "AM"
                color: root.clSurfaceFg
                font {
                    family: root.clockFontFamily
                    pointSize: Math.max(1, Math.round(20 * root.centerScale))
                    weight: Font.Normal
                    variableAxes: ({ "wdth": 100 })
                }

                TextMetrics {
                    id: amPmMetrics
                    text: amPm.text
                    font: amPm.font
                }
            }
        }
    }

    Text {
        id: dateText
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDate(root.currentTime, "dddd • d MMM").toUpperCase()
        font {
            family: root.clockFontFamily
            pointSize: Math.max(10, Math.round(14 * root.centerScale))
            weight: Font.DemiBold
            letterSpacing: 1.5
        }
        color: root.clSurfaceFg
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.currentTime = new Date()
    }
}
