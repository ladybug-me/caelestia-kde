
import QtQuick
import ".."
import QtQuick.Layouts

Rectangle {
    id: root

    property var greetingInfo: ({ greeting: "Good day", icon: "sunny", iconColor: "#9bd0cc" })
    property string userName: "User"
    property real centerScale: 1.0
    property real centerWidth: 600 * centerScale

    property color pillColor: Qt.rgba(255, 255, 255, 0.08)
    property color clSurfaceVariantFg: "#a2adac"
    property color clPrimary: "#9bd0cc"

    color: pillColor
    radius: height / 2
    implicitWidth: Math.max(
        greetingRow.implicitWidth + Math.max(16, Math.round(20 * root.centerScale)),
        Math.min(root.centerWidth, greetingRow.implicitWidth + Math.max(20, Math.round(28 * root.centerScale)))
    )
    implicitHeight: Math.max(26, Math.round(38 * root.centerScale))

    RowLayout {
        id: greetingRow
        anchors.centerIn: parent
        spacing: Math.max(3, Math.round(6 * root.centerScale))

        Text {
            text: root.greetingInfo ? (root.greetingInfo.icon || "") : ""
            font.family: "Material Symbols Rounded"
            font.pixelSize: Math.max(13, Math.round(17 * root.centerScale))
            color: root.greetingInfo ? (root.greetingInfo.iconColor || root.clPrimary) : root.clPrimary
        }
        RowLayout {
            spacing: Math.max(2, Math.round(4 * root.centerScale))
            Text {
                text: (root.greetingInfo ? root.greetingInfo.greeting : "") + ","
                color: root.clSurfaceVariantFg
                font { pixelSize: Math.max(11, Math.round(13 * root.centerScale)); family: "Rubik" }
                elide: Text.ElideRight
            }
            Text {
                text: root.userName || "User"
                color: root.clPrimary
                font { pixelSize: Math.max(11, Math.round(13 * root.centerScale)); family: "Rubik"; weight: Font.Bold }
                elide: Text.ElideRight
            }
        }
    }
}
