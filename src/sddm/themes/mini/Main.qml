pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "components"
import "singletons"

Rectangle {
    id: root

    property bool firstInput: Theme.enableWelcomeMessage
    property string buffer: ""
    property bool capsLockOn: (typeof keyboard !== 'undefined') ? keyboard.capsLock : false
    property var userName: {
        if (userModel.count > 0 && userModel.lastIndex >= 0) {
            const idx = userModel.index(userModel.lastIndex, 0);
            return userModel.data(idx, Qt.UserRole + 1);
        }
        return "";
    }

    function restoreFocus() {
        if (!keyHandler.activeFocus)
            keyHandler.forceActiveFocus();
    }

    function clearBuffer() {
        root.buffer = "";
    }

    width: 1920
    height: 1080
    color: Theme.mSurface

    FontLoader {
        id: googleSansFlex

        source: "assets/google-sans-flex/GoogleSansFlex.ttf"
    }

    Item {
        id: keyHandler

        focus: true
        Component.onCompleted: {
            keyHandler.forceActiveFocus();
        }
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_CapsLock) {
                root.capsLockOn = !root.capsLockOn;
                return;
            }
            if (event.text && event.text.length === 1) {
                const charStr = event.text.charAt(0);
                if ((charStr >= "a" && charStr <= "z") || (charStr >= "A" && charStr <= "Z")) {
                    const isUpper = (charStr === charStr.toUpperCase());
                    const shiftPressed = (event.modifiers & Qt.ShiftModifier) ? true : false;
                    root.capsLockOn = (isUpper && !shiftPressed) || (!isUpper && shiftPressed);
                }
            }
            if (root.firstInput) {
                loginCard.clearError();
                if (event.text && event.text !== "" && event.text.length === 1)
                    root.buffer = event.text;

                root.firstInput = false;
                return;
            }
            if (event.key === Qt.Key_Escape) {
                if (Theme.enableWelcomeMessage)
                    root.firstInput = true;

                root.clearBuffer();
                return;
            }
            if (event.key === Qt.Key_Right) {
                if (userModel.count > 0 && loginCard.currentUserIndex < userModel.count - 1) {
                    loginCard.currentUserIndex += 1;
                    root.clearBuffer();
                }
                return;
            }
            if (event.key === Qt.Key_Left) {
                if (userModel.count > 0 && loginCard.currentUserIndex > 0) {
                    loginCard.currentUserIndex -= 1;
                    root.clearBuffer();
                }
                return;
            }
            if (event.key === Qt.Key_Up) {
                if (sessionModel.count > 0 && loginCard.currentSessionIndex > 0)
                    loginCard.currentSessionIndex -= 1;

                return;
            }
            if (event.key === Qt.Key_Down) {
                if (sessionModel.count > 0 && loginCard.currentSessionIndex < sessionModel.count - 1)
                    loginCard.currentSessionIndex += 1;

                return;
            }
            if (event.key === Qt.Key_Backspace) {
                loginCard.clearError();
                root.buffer = root.buffer.slice(0, -1);
                return;
            }
            if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                loginCard.showAuthenticating();
                sddm.login(loginCard.getUserName(loginCard.currentUserIndex), root.buffer, loginCard.currentSessionIndex);
                root.clearBuffer();
                return;
            }
            if (event.text && event.text !== "" && event.text.length === 1) {
                // Clear the error once the user types again.
                loginCard.clearError();
                root.buffer += event.text;
            }
            // DEBUG: Shift+F to simulate failed login (toggle via debugMode in theme.conf)
            if (Theme.debugMode && event.key === Qt.Key_F && (event.modifiers & Qt.ShiftModifier)) {
                loginCard.showError("Incorrect password");
                root.clearBuffer();
                return;
            }
        }
    }

    AnimatedImage {
        id: background

        anchors.fill: parent
        source: Theme.backgroundSource
        fillMode: Image.PreserveAspectCrop

        Loader {
            id: videoLoader

            anchors.fill: parent
            source: "components/VideoBackground.qml"
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.mShadow
            opacity: root.firstInput ? 0 : Theme.overlayOpacity

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.enableWelcomeMessage ? Theme.animDurationNormal : 0
                }
            }
        }
    }

    MultiEffect {
        source: background
        anchors.fill: background
        blurEnabled: Theme.blurEnabled
        blur: root.firstInput ? 0 : Theme.blurStrength
        blurMax: 64
        blurMultiplier: 1
        autoPaddingEnabled: false

        Behavior on blur {
            NumberAnimation {
                duration: Theme.enableWelcomeMessage ? Theme.animDurationSlow : 0
            }
        }
    }

    WelcomeHeading {
        userName: root.userName
        isActive: root.firstInput
    }

    LoginCard {
        id: loginCard

        anchors.centerIn: parent
        isActive: root.firstInput
        usersModel: userModel
        sessionsModel: sessionModel
        buffer: root.buffer
        capsLockOn: root.capsLockOn
        onRestoreFocus: root.restoreFocus
        onCurrentUserIndexChanged: {
            root.clearBuffer();
        }
        onLogin: function () {
            loginCard.showAuthenticating();
            sddm.login(loginCard.getUserName(loginCard.currentUserIndex), root.buffer, loginCard.currentSessionIndex);
            root.clearBuffer();
            root.restoreFocus();
        }
    }

    Connections {
        function onLoginFailed() {
            loginCard.clearAuthenticating();
            loginCard.showError("Incorrect password");
            root.clearBuffer();
            root.restoreFocus();
        }

        function onLoginSucceeded() {
            loginCard.clearAuthenticating();
            loginCard.clearError();
        }

        target: sddm
    }

    Text {
        renderType: Text.NativeRendering
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        font.family: Theme.fontFamily
        font.pixelSize: 20
        font.italic: true
        opacity: root.firstInput ? 1 : 0
        color: Theme.mOnSurfaceVariant
        text: "Press any key to login"

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animDurationNormal
                easing.type: Easing.OutCubic
            }
        }
    }
}
