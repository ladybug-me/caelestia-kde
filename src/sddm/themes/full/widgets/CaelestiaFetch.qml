import "../components"
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property bool firstInput
    required property string currentSessionName
    required property string currentUser
    required property int rectHeight

    property string os: (config.os || "Linux").split(" ")[0]
    property string host: config.host || "localhost"
    property string session: (root.currentSessionName || "Hyprland").split(" ")[0]

    RowLayout {
        Rectangle {
            width: 33
            height: 35
            radius: 13
            Layout.leftMargin: 23
            Layout.topMargin: 25
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            color: config.secondary

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                color: "#111111"
                text: ">"
                font.family: "CaskaydiaCove NF"
                font.pointSize: 15
            }
        }

        Text {
            renderType: Text.NativeRendering
            color: config.text
            text: "caelestiafetch.sh"
            font.family: "CaskaydiaCove NF"
            font.pointSize: 13
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            Layout.topMargin: 32
            Layout.leftMargin: 8
        }
    }

    ColumnLayout {
        Item {
            width: 30
            height: 30
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter

            Logo {
                skipIntroAnimation: root.firstInput
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                Layout.leftMargin: 25
                Layout.topMargin: 50
                Layout.preferredWidth: 130
                Layout.preferredHeight: 130
            }

            RowLayout {
                spacing: 10

                Text {
                    renderType: Text.NativeRendering
                    Layout.leftMargin: 12
                    Layout.topMargin: root.rectHeight / 10
                    text: "WM     :\nUSER   :\nOS     :\nHOST   :"
                    color: config.text
                    font.pixelSize: 18
                    font.family: "CaskaydiaCove NF"
                    lineHeight: 30
                    lineHeightMode: Text.FixedHeight
                    Layout.preferredWidth: 80
                }

                Text {
                    renderType: Text.NativeRendering
                    Layout.leftMargin: 0
                    Layout.topMargin: root.rectHeight / 10
                    text: root.session + "\n" + root.currentUser + "\n" + root.os + "\n" + root.host
                    color: config.text
                    font.pixelSize: 18
                    font.family: "CaskaydiaCove NF"
                    lineHeight: 30
                    lineHeightMode: Text.FixedHeight
                    Layout.preferredWidth: 100
                }
            }
        }

        RowLayout {
            spacing: 20
            Layout.alignment: Qt.AlignHCenter
            Layout.leftMargin: 30
            Layout.topMargin: 4

            Rectangle {
                width: 30
                height: 30
                color: config.background
                radius: 12
            }

            Rectangle {
                width: 30
                height: 30
                color: config.primary
                radius: 12
            }

            Rectangle {
                width: 30
                height: 30
                color: config.text
                radius: 12
            }

            Rectangle {
                width: 30
                height: 30
                color: config.textDark
                radius: 12
            }

            Rectangle {
                width: 30
                height: 30
                color: config.secondary
                radius: 12
            }

            Rectangle {
                width: 30
                height: 30
                color: config.onSuccess
                radius: 12
            }

            Rectangle {
                width: 30
                height: 30
                color: config.inverseOnSurface
                radius: 12
            }
        }
    }
}
