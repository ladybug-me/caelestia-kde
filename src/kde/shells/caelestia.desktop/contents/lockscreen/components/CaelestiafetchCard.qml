
import QtQuick
import ".."
import QtQuick.Layouts
import QtQuick.Effects

Rectangle {
    id: root

    property var fetchInfo: null
    property var clTerms: []
    property real centerScale: 1.0

    property color clSurfaceContainer: "#131b1a"
    property color clSurfaceContainerHigh: "#192120"
    property color clSurfaceContainerHighest: "#1d2827"
    property color clSurface: "#0a0f0f"
    property color clSurfaceFg: "#dce8e6"
    property color clSurfaceVariantFg: "#a2adac"
    property color clPrimary: "#9bd0cc"
    property bool recolourLogo: true

    property real cardRadius: 26
    radius: cardRadius
    color: clSurfaceContainer
    clip: true

    implicitHeight: (36 + 180 + 28 + 2 * 12 + 2 * 18) * centerScale

    readonly property string logoPath: {
        if (fetchInfo && fetchInfo.logoPath) return fetchInfo.logoPath;
        return "";
    }

    readonly property bool showLargeLogo: root.width >= (280 * root.centerScale)

    readonly property var fetchLines: {
        var osStr = "";
        var wmStr = "KDE";
        var userStr = "";
        var upStr = "";

        if (fetchInfo) {
            if (typeof fetchInfo === "object" && !Array.isArray(fetchInfo)) {
                if (fetchInfo.os)     osStr   = fetchInfo.os;
                if (fetchInfo.wm)     wmStr   = fetchInfo.wm;
                if (fetchInfo.user)   userStr = fetchInfo.user;
                if (fetchInfo.uptime) upStr   = fetchInfo.uptime;
            } else if (Array.isArray(fetchInfo)) {
                for (var i = 0; i < fetchInfo.length; i++) {
                    var item = fetchInfo[i];
                    if (item.type === "OS") osStr = item.result.name || osStr;
                    else if (item.type === "WM") wmStr = item.result.name || wmStr;
                    else if (item.type === "USER") userStr = item.result.name || userStr;
                    else if (item.type === "Uptime") {
                        var s = item.result.uptime > 1000000 ? Math.floor(item.result.uptime / 1000) : item.result.uptime;
                        var h = Math.floor(s / 3600);
                        var m = Math.floor((s % 3600) / 60);
                        upStr = (h > 0 ? (h + " hours, ") : "") + m + " mins";
                    }
                }
            }
        }

        var lines = [];
        if (root.height >= 180 * root.centerScale) {
            lines.push("OS  : " + osStr);
            lines.push("WM  : " + wmStr);
            lines.push("USER: " + userStr);
            lines.push("UP  : " + upStr);
        } else if (root.height >= 140 * root.centerScale) {
            lines.push("OS  : " + osStr);
            lines.push("USER: " + userStr);
            lines.push("UP  : " + upStr);
        } else {
            lines.push("OS  : " + osStr);
            lines.push("UP  : " + upStr);
        }
        return lines;
    }

    readonly property real bodyLogoSize: Math.round(Math.min(root.height * 0.48, root.width * 0.30))

    ColumnLayout {
        id: fetchLayout
        anchors.fill: parent
        anchors.margins: Math.max(10, 14 * root.centerScale)
        spacing: Math.max(4, 8 * root.centerScale)

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 8 * root.centerScale

            Rectangle {
                implicitWidth: Math.max(22, 28 * root.centerScale)
                implicitHeight: implicitWidth
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                radius: Math.max(6, 8 * root.centerScale)
                color: root.clPrimary

                Text {
                    anchors.centerIn: parent
                    text: ">"
                    font {
                        pixelSize: LockScreenConfig.sizeNormal
                        family: LockScreenConfig.fontMetrics
                        weight: Font.Bold
                    }
                    color: root.clSurface
                }
            }

            Text {
                text: "caelestiafetch.sh"
                font {
                    pixelSize: LockScreenConfig.sizeNormal
                    family: LockScreenConfig.fontMetrics
                }
                color: root.clSurfaceFg
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Item {
                id: titlebarLogo
                visible: !root.showLargeLogo && root.logoPath.length > 0
                implicitWidth: Math.max(22, 26 * root.centerScale)
                implicitHeight: implicitWidth
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: titlebarDistroIcon
                    anchors.fill: parent
                    source: root.logoPath
                    sourceSize.width: 128
                    sourceSize.height: 128
                    fillMode: Image.PreserveAspectFit
                    visible: false
                }

                MultiEffect {
                    anchors.fill: titlebarDistroIcon
                    source: titlebarDistroIcon
                    colorization: root.recolourLogo ? 1.0 : 0.0
                    colorizationColor: root.clPrimary
                    brightness: root.recolourLogo ? 0.5 : 0.0
                }
            }
        }

        RowLayout {
            id: bodyRow
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Layout.fillHeight: true
            spacing: root.showLargeLogo ? Math.max(10, Math.round(16 * root.centerScale)) : 0

            Item {
                id: logoContainer
                visible: root.showLargeLogo && root.logoPath.length > 0
                implicitWidth: visible ? root.bodyLogoSize : 0
                implicitHeight: visible ? root.bodyLogoSize : 0
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: distroIcon
                    anchors.fill: parent
                    anchors.margins: 2 * root.centerScale
                    source: root.logoPath
                    sourceSize.width: 512
                    sourceSize.height: 512
                    fillMode: Image.PreserveAspectFit
                    visible: false
                }

                MultiEffect {
                    anchors.fill: distroIcon
                    source: distroIcon
                    colorization: root.recolourLogo ? 1.0 : 0.0
                    colorizationColor: root.clPrimary
                    brightness: root.recolourLogo ? 0.5 : 0.0
                }
            }

            ColumnLayout {
                id: textColumn
                Layout.alignment: Qt.AlignVCenter
                spacing: Math.max(2, 5 * root.centerScale)

                Repeater {
                    model: root.fetchLines

                    Text {
                        required property string modelData
                        text: modelData
                        font {
                            family: LockScreenConfig.fontMetrics
                            pixelSize: (root.width > (340 * root.centerScale) && root.height > (190 * root.centerScale))
                                       ? LockScreenConfig.sizeNormal
                                       : LockScreenConfig.sizeVerySmall
                        }
                        color: root.clSurfaceFg
                        elide: Text.ElideRight
                    }
                }
            }
        }

        RowLayout {
            id: coloursRow
            visible: (root.centerScale >= 0.85) && (root.height >= 170 * root.centerScale)
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: false
            Layout.preferredHeight: visible ? -1 : 0
            Layout.topMargin: visible ? (2 * root.centerScale) : 0
            spacing: Math.max(4, 10 * root.centerScale)

            Repeater {
                model: root.clTerms && root.clTerms.length
                       ? root.clTerms.slice(0, Math.min(7, Math.max(0, Math.floor((root.width - 32 * root.centerScale) / (20 * root.centerScale)))))
                       : []

                Rectangle {
                    required property string modelData
                    readonly property real dotSize: Math.max(10, Math.min(25 * root.centerScale, (root.width - 64 * root.centerScale) / 9))
                    implicitWidth: dotSize
                    implicitHeight: dotSize
                    Layout.preferredWidth: dotSize
                    Layout.preferredHeight: dotSize
                    radius: dotSize / 2
                    color: modelData
                }
            }
        }
    }
}
