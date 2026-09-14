
import QtQuick
import ".."
import QtQuick.Layouts
import M3Shapes
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.sessions

FocusScope {
    id: root

    property real centerScale: 1.0
    property real centerWidth: 600 * centerScale
    property real pillWidth: 0
    property bool isAuthenticating: false
    property bool graceLocked: false
    property bool hasFingerprint: false
    property bool fprintDisabledDueToTries: false
    property bool lockoutActive: false
    property string lockoutText: ""

    property color clSurfaceContainer: "#131b1a"
    property color clSurfaceContainerHigh: "#192120"
    property color clSurfaceFg: "#dce8e6"
    property color clSurfaceVariantFg: "#a2adac"
    property color clPrimary: "#9bd0cc"
    property color clPrimaryFg: "#0d4845"
    property color clSecondary: "#b0ccc9"
    property color clError: "#fa746f"

    property alias text: passwordBox.text
    property real shakeX: 0

    signal loginRequested(string password)

    function shake() {
        rejectAnim.restart();
    }

    function clearPassword() {
        passwordBox.forceActiveFocus();
        passwordBox.text = "";
        passwordBox.text = Qt.binding(() => PasswordSync.password);
    }

    readonly property var shapeQueue: {
        var shapes = [
            MaterialShape.Slanted, MaterialShape.Arch, MaterialShape.Fan, MaterialShape.Arrow,
            MaterialShape.SemiCircle, MaterialShape.Triangle, MaterialShape.Diamond, MaterialShape.ClamShell,
            MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny, MaterialShape.VerySunny,
            MaterialShape.Cookie4Sided, MaterialShape.Ghostish, MaterialShape.SoftBurst
        ];
        for (var i = shapes.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var tmp = shapes[i];
            shapes[i] = shapes[j];
            shapes[j] = tmp;
        }
        return shapes;
    }

    TextMetrics {
        id: placeholderMetrics
        text: root.isAuthenticating ? qsTr("Loading...") : (root.graceLocked ? qsTr("Please wait...") : (root.lockoutActive && root.lockoutText.length > 0 ? root.lockoutText : qsTr("Enter your password")))
        font { pixelSize: Math.max(11, Math.round(13 * root.centerScale)); family: LockScreenConfig.fontHeading; weight: Font.Normal }
    }

    readonly property real nonInputWidth: {
        var leftM = Math.max(6, Math.round(10 * root.centerScale));
        var rightM = Math.max(4, Math.round(6 * root.centerScale));
        var sp = Math.max(3, Math.round(6 * root.centerScale));
        var iconW = Math.max(16, Math.round(22 * root.centerScale));
        var btnW = Math.max(20, Math.round(28 * root.centerScale));
        return leftM + iconW + (sp * 2) + btnW + rightM;
    }

    readonly property real collapsedWidth: nonInputWidth + placeholderMetrics.width
    readonly property real targetExpandedWidth: root.pillWidth > 0 ? root.pillWidth : root.centerWidth
    readonly property real expandedWidth: Math.max(collapsedWidth, targetExpandedWidth)

    implicitWidth: passwordBox.text.length > 0 ? expandedWidth : collapsedWidth
    implicitHeight: Math.max(28, Math.round(42 * root.centerScale))
    transform: Translate { x: root.shakeX }

    Behavior on implicitWidth {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: rejectAnim
        NumberAnimation { target: root; property: "shakeX"; to: -20; duration: 80; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 16; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -10; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 120; easing.type: Easing.OutQuad }
    }

    Rectangle {
        id: pillBg
        anchors.fill: parent
        radius: height / 2
        color: root.clSurfaceContainer
        border.color: root.lockoutActive ? root.clError : "transparent"
        border.width: root.lockoutActive ? Math.max(1, Math.round(1.5 * root.centerScale)) : 0
        Behavior on border.color { ColorAnimation { duration: 250 } }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: passwordBox.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Math.max(6, Math.round(10 * root.centerScale))
            anchors.rightMargin: Math.max(4, Math.round(6 * root.centerScale))
            spacing: Math.max(3, Math.round(6 * root.centerScale))

            Item {
                id: iconWrapper
                Layout.preferredWidth: Math.max(16, Math.round(22 * root.centerScale))
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignVCenter

                Text {
                    anchors.centerIn: parent
                    text: root.fprintDisabledDueToTries ? "fingerprint_off" : (root.hasFingerprint ? "fingerprint" : "lock")
                    font.family: LockScreenConfig.fontIcon
                    font.pixelSize: Math.max(12, Math.round(16 * root.centerScale))
                    color: (root.graceLocked || root.lockoutActive) ? root.clError : (root.fprintDisabledDueToTries ? root.clError : root.clSurfaceVariantFg)
                    visible: !root.isAuthenticating
                    Behavior on color { ColorAnimation { duration: 250 } }
                }

                Item {
                    id: spinner
                    anchors.centerIn: parent
                    width: 18 * root.centerScale; height: width
                    visible: root.isAuthenticating
                    Rectangle {
                        width: parent.width * 0.3; height: width; radius: width / 2
                        color: root.clPrimary
                        x: parent.width / 2 - width / 2; y: 0
                    }
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1200
                        loops: Animation.Infinite; running: spinner.visible
                    }
                }
            }

            Item {
                id: inputContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Text {
                    id: placeholder
                    anchors.centerIn: parent
                    text: placeholderMetrics.text
                    font: placeholderMetrics.font
                    color: (root.lockoutActive && !root.isAuthenticating && !root.graceLocked) ? root.clError : (root.isAuthenticating ? root.clSecondary : root.clSurfaceVariantFg)
                    opacity: passwordBox.text.length > 0 ? 0 : 1
                    Behavior on color { ColorAnimation { duration: 250 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                ListModel {
                    id: charModel
                }

                ListView {
                    id: charList
                    anchors.centerIn: parent
                    orientation: Qt.Horizontal
                    spacing: 6 * root.centerScale
                    height: 18 * root.centerScale
                    width: Math.min(parent.width, (count * height) + Math.max(0, count - 1) * spacing)
                    model: charModel
                    interactive: false

                    delegate: Item {
                        id: ch
                        required property int index
                        required property int shapeVal
                        property real nonAnimWidthScale: 1.0
                        width: charList.height * nonAnimWidthScale
                        height: charList.height

                        ListView.onRemove: {
                            initAnim.stop();
                            removeAnim.start();
                        }

                        MaterialShape {
                            id: charShape
                            anchors.centerIn: parent
                            implicitSize: charList.height * 1.4
                            shape: shapeVal
                            color: root.clSurfaceFg

                            SequentialAnimation {
                                id: initAnim
                                running: true
                                ParallelAnimation {
                                    NumberAnimation { target: charShape; property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: charShape; property: "scale"; from: 0; to: 1; duration: 180; easing.type: Easing.OutBack }
                                    NumberAnimation { target: ch; property: "nonAnimWidthScale"; from: 1.0; to: 1.3; duration: 150 }
                                }
                                PauseAnimation { duration: 180 }
                                PropertyAction { target: charShape; property: "shape"; value: MaterialShape.Circle }
                                ParallelAnimation {
                                    NumberAnimation { target: charShape; property: "scale"; to: 2 / 3; duration: 180; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: ch; property: "nonAnimWidthScale"; to: 1.0; duration: 150 }
                                }
                            }

                            SequentialAnimation {
                                id: removeAnim
                                PropertyAction { target: ch; property: "ListView.delayRemove"; value: true }
                                ParallelAnimation {
                                    NumberAnimation { target: charShape; property: "opacity"; to: 0; duration: 120 }
                                    NumberAnimation { target: charShape; property: "scale"; to: 0.5; duration: 120 }
                                }
                                PropertyAction { target: ch; property: "ListView.delayRemove"; value: false }
                            }
                        }
                    }
                }

                TextInput {
                    id: passwordBox
                    anchors.fill: parent
                    color: "transparent"
                    cursorVisible: false
                    cursorDelegate: Item {}
                    echoMode: TextInput.NoEcho
                    focus: true
                    enabled: !root.graceLocked && !root.isAuthenticating
                    text: PasswordSync.password

                    onTextChanged: {
                        var targetLen = text.length;
                        while (charModel.count < targetLen) {
                            var idx = charModel.count;
                            charModel.append({ shapeVal: root.shapeQueue[idx % root.shapeQueue.length] });
                        }
                        while (charModel.count > targetLen) {
                            charModel.remove(charModel.count - 1);
                        }
                    }

                    onAccepted: if (!root.graceLocked && !root.isAuthenticating) root.loginRequested(passwordBox.text)
                }
                Binding { target: PasswordSync; property: "password"; value: passwordBox.text }
            }

            Item {
                id: enterButton
                implicitWidth: Math.max(20, Math.round(28 * root.centerScale))
                implicitHeight: implicitWidth
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignVCenter

                MaterialShape {
                    id: enterShape
                    anchors.fill: parent
                    color: passwordBox.text.length > 0 ? ((root.graceLocked || root.lockoutActive) ? root.clError : root.clPrimary) : root.clSurfaceContainerHigh
                    shape: passwordBox.text.length > 0 ? MaterialShape.Arrow : MaterialShape.Circle
                    rotation: 90
                    scale: passwordBox.text.length === 0 ? 1.0 : (enterMouse.pressed ? 0.6 : (enterMouse.containsMouse ? 0.8 : 0.7))

                    Behavior on color { ColorAnimation { duration: 250 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    MouseArea {
                        id: enterMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: (passwordBox.text.length > 0 && !root.graceLocked && !root.isAuthenticating) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (passwordBox.text.length > 0 && !root.isAuthenticating && !root.graceLocked) root.loginRequested(passwordBox.text)
                    }
                }

                Text {
                    id: enterIcon
                    anchors.centerIn: parent
                    text: "arrow_forward"
                    font.family: LockScreenConfig.fontIcon
                    font.pixelSize: Math.max(11, Math.round(14 * root.centerScale))
                    color: passwordBox.text.length > 0 ? root.clPrimaryFg : root.clSurfaceVariantFg
                    opacity: passwordBox.text.length > 0 ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }
        }
    }
}
