pragma ComponentBehavior: Bound
import "../singletons"
import Qt5Compat.GraphicalEffects
import QtQuick

Item {
    id: root

    property bool isActive: true
    property var usersModel: null
    property var sessionsModel: null
    property string buffer: ""
    property var onRestoreFocus: null
    property var onLogin: null
    property bool isError: false
    property bool isAuthenticating: false
    property bool capsLockOn: false
    property int currentUserIndex: 0
    // SDDM exposes session names through SessionModel::NameRole, which is not
    // addressable by name outside a delegate.
    readonly property int sessionNameRole: Qt.UserRole + 4
    property int currentSessionIndex: sessionsModel && sessionsModel.count > 0 ? sessionsModel.lastIndex : 0

    function getUserName(idx) {
        if (!usersModel || usersModel.count <= 0 || idx < 0 || idx >= usersModel.count)
            return "";

        var modelIndex = usersModel.index(idx, 0);
        return usersModel.data(modelIndex, Qt.UserRole + 1);
    }

    function getSessionName(idx) {
        if (!sessionsModel || idx < 0 || idx >= sessionsModel.count)
            return "";

        return sessionsModel.data(sessionsModel.index(idx, 0), root.sessionNameRole);
    }

    function showError(msg) {
        root.isError = true;
        root.isAuthenticating = false;
        toast.show(msg);
    }

    function clearError() {
        root.isError = false;
    }

    function showAuthenticating() {
        root.isAuthenticating = true;
    }

    function clearAuthenticating() {
        root.isAuthenticating = false;
    }

    enabled: !isActive
    width: 550
    height: 850
    scale: isActive ? 0.5 : 1
    opacity: isActive ? 0 : 1
    onUsersModelChanged: {
        if (usersModel && usersModel.count > 0) {
            const uIdx = usersModel.lastIndex;
            currentUserIndex = (uIdx >= 0 && uIdx < usersModel.count) ? uIdx : 0;
        }
    }
    onCapsLockOnChanged: {
        if (capsLockOn && !isAuthenticating) {
            toast.show("Caps Lock is on", "warning");
        } else if (!capsLockOn) {
            if (toast.isOpen && toast.message === "Caps Lock is on")
                toast.dismiss();
        }
    }
    onIsActiveChanged: {
        if (isActive)
            toast.dismiss();
    }
    Component.onCompleted: {
        if (usersModel && usersModel.count > 0) {
            const uIdx = usersModel.lastIndex;
            currentUserIndex = (uIdx >= 0 && uIdx < usersModel.count) ? uIdx : 0;
        }
    }

    Rectangle {
        id: cardBorder

        anchors.fill: mainCard
        anchors.margins: Theme.cardBorder ? -2 : 0
        radius: Theme.cardRadius + (Theme.cardBorder ? 2 : 0)
        color: "transparent"
        border.color: Theme.mHover
        border.width: Theme.cardBorder ? 2 : 0
        z: -1
    }

    DropShadow {
        anchors.fill: mainCard
        horizontalOffset: 0
        verticalOffset: 4
        radius: Theme.shadowRadius
        samples: Theme.shadowSamples
        spread: 0.05
        color: Theme.withAlpha(Theme.mShadow, 0.25)
        source: mainCard
        visible: Theme.dropShadows
        transparentBorder: true
    }

    Rectangle {
        id: mainCard

        anchors.fill: parent
        radius: Theme.cardRadius
        color: Theme.withAlpha(Theme.mSurface, Theme.outerCardOpacity)

        BlurWrapper {
            anchors.fill: parent
            targetWidth: mainCard.width
            targetHeight: mainCard.height
            animDuration: Theme.enableWelcomeMessage ? Theme.animDurationNormal : 0
            blurEnabled: Theme.cardBlurEnabled
            blurAmount: Theme.cardBlurStrength
            radius: mainCard.radius
            source: Qt.resolvedUrl("../assets/background")
            z: -1
        }

        Rectangle {
            id: subCard

            anchors.fill: parent
            anchors.margins: 16
            radius: Theme.cardRadius - 16
            color: Theme.withAlpha(Theme.mSurfaceContainer, Theme.innerCardOpacity)

            Column {
                id: mainContent

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -30
                spacing: 20

                Clock {
                    id: clock

                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Avatar {
                    id: avatar

                    anchors.horizontalCenter: parent.horizontalCenter
                    currentUserIndex: root.currentUserIndex
                    userModel: root.usersModel
                    onSwitchUser: function () {
                        if (root.usersModel && root.usersModel.count > 0) {
                            root.currentUserIndex = (root.currentUserIndex + 1) % root.usersModel.count;
                            if (root.onRestoreFocus)
                                root.onRestoreFocus();
                        }
                    }
                }

                Row {
                    id: userSessionRow

                    readonly property var textAxes: ({
                            "wght": 550,
                            "wdth": 40,
                            "ROND": 25,
                            "opsz": 7
                        })

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    bottomPadding: 10

                    Text {
                        id: userText

                        renderType: Text.QtRendering
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.variableAxes: userSessionRow.textAxes
                        color: userMouseArea.containsMouse ? Theme.mOnSurface : Theme.mPrimary
                        text: root.getUserName(root.currentUserIndex)
                        scale: 1.0 + userBounce.bounce

                        TapBounce {
                            id: userBounce
                        }

                        MouseArea {
                            id: userMouseArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                userBounce.trigger();
                                if (root.usersModel && root.usersModel.count > 0) {
                                    root.currentUserIndex = (root.currentUserIndex + 1) % root.usersModel.count;
                                    if (root.onRestoreFocus)
                                        root.onRestoreFocus();
                                }
                            }
                        }
                    }

                    Text {
                        id: separatorText

                        renderType: Text.NativeRendering
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        height: userText.height
                        verticalAlignment: Text.AlignVCenter
                        font.bold: true
                        color: Theme.mSecondary
                        text: "|"
                    }

                    Text {
                        id: sessionText

                        renderType: Text.QtRendering
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.variableAxes: userSessionRow.textAxes
                        color: sessionMouseArea.containsMouse ? Theme.mOnSurface : Theme.mPrimary
                        text: root.getSessionName(root.currentSessionIndex)
                        scale: 1.0 + sessionBounce.bounce

                        TapBounce {
                            id: sessionBounce
                        }

                        MouseArea {
                            id: sessionMouseArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                sessionBounce.trigger();
                                if (root.sessionsModel && root.sessionsModel.count > 0) {
                                    root.currentSessionIndex = (root.currentSessionIndex + 1) % root.sessionsModel.count;
                                    if (root.onRestoreFocus)
                                        root.onRestoreFocus();
                                }
                            }
                        }
                    }
                }

                PasswordInput {
                    id: passwordInput

                    anchors.horizontalCenter: parent.horizontalCenter
                    buffer: root.buffer
                    isError: root.isError
                    isAuthenticating: root.isAuthenticating
                    capsLockOn: root.capsLockOn
                    onRestoreFocus: root.onRestoreFocus
                    onLogin: root.onLogin
                }

                Row {
                    id: powerButtons

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20
                    topPadding: 10

                    PowerButton {
                        id: shutBtn

                        width: 70
                        height: 70
                        iconText: "power_settings_new"
                        onRestoreFocus: root.onRestoreFocus
                        onClickedAction: function () {
                            sddm.powerOff();
                        }
                    }

                    PowerButton {
                        id: rebBtn

                        width: 70
                        height: 70
                        iconText: "restart_alt"
                        onRestoreFocus: root.onRestoreFocus
                        onClickedAction: function () {
                            sddm.reboot();
                        }
                    }
                }
            }

            Row {
                id: controlHints

                anchors.bottom: parent.bottom
                anchors.bottomMargin: 30
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 13

                Row {
                    spacing: 4

                    Text {
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 13
                        color: Theme.mOnSurfaceVariant
                        text: "touch_app"
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.mOnSurfaceVariant
                        text: "Click to switch User and Session"
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    ToastMessage {
        id: toast

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -16
        onDismissed: root.clearError()
    }

    Behavior on scale {
        NumberAnimation {
            duration: Theme.enableWelcomeMessage ? Theme.animDurationNormal : 0
            easing.type: Easing.OutBack
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.enableWelcomeMessage ? Theme.animDurationNormal : 0
            easing.type: Easing.OutBack
        }
    }
}
