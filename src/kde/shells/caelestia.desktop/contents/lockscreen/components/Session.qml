
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.private.sessions
import ".."

Item {
    id: root

    implicitWidth: visibleActions.length > 0 ? contentCol.implicitWidth : 0
    implicitHeight: visibleActions.length > 0 ? (actionsRow.height + Math.max(12, Math.round(14 * root.centerScale)) + contentCol.spacing) : 0
    width: implicitWidth
    height: implicitHeight

    property bool isAuthenticating: false
    property real centerScale: 1.0

    property color clPrimary
    property color clSurfaceVariantFg
    property color clSurfaceFg: clPrimary

    property SessionManagement sessionManagement: null
    property int confirmationMode: 0 // SessionManagement.ConfirmationMode.Skip
    property var customIcons: ({})

    property bool showSleep: true
    property bool showHibernate: false
    property bool showSwitchUser: true
    property bool showLogout: true
    property bool showReboot: false
    property bool showShutdown: false

    property string hoveredAction: ""
    property string hoveredLabel: ""

    signal actionTriggered(string action)

    readonly property SessionManagement activeSessionManagement: root.sessionManagement || defaultSessionManagement

    readonly property bool canSuspend: activeSessionManagement ? Boolean(activeSessionManagement.canSuspend) : true
    readonly property bool canHibernate: activeSessionManagement ? Boolean(activeSessionManagement.canHibernate) : false
    readonly property bool canSwitchUser: activeSessionManagement ? Boolean(activeSessionManagement.canSwitchUser) : true
    readonly property bool canLogout: activeSessionManagement ? Boolean(activeSessionManagement.canLogout) : true
    readonly property bool canReboot: activeSessionManagement ? Boolean(activeSessionManagement.canReboot) : true
    readonly property bool canShutdown: activeSessionManagement ? Boolean(activeSessionManagement.canShutdown) : true

    readonly property var visibleActions: {
        var actions = [];

        if (root.showSleep && root.canSuspend) {
            actions.push({
                actionId: "suspend",
                icon: (root.customIcons && root.customIcons.suspend) ? root.customIcons.suspend : "bedtime",
                label: qsTr("Sleep"),
                trigger: () => root.suspend()
            });
        }

        if (root.showHibernate && root.canHibernate) {
            actions.push({
                actionId: "hibernate",
                icon: (root.customIcons && root.customIcons.hibernate) ? root.customIcons.hibernate : "mode_night",
                label: qsTr("Hibernate"),
                trigger: () => root.hibernate()
            });
        }

        if (root.showSwitchUser && root.canSwitchUser) {
            actions.push({
                actionId: "switchUser",
                icon: (root.customIcons && root.customIcons.switchUser) ? root.customIcons.switchUser : "manage_accounts",
                label: qsTr("Switch User"),
                trigger: () => root.switchUser()
            });
        }

        if (root.showLogout && root.canLogout) {
            actions.push({
                actionId: "logout",
                icon: (root.customIcons && root.customIcons.logout) ? root.customIcons.logout : "logout",
                label: qsTr("Log Out"),
                trigger: () => root.logout()
            });
        }

        if (root.showReboot && root.canReboot) {
            actions.push({
                actionId: "reboot",
                icon: (root.customIcons && root.customIcons.reboot) ? root.customIcons.reboot : "restart_alt",
                label: qsTr("Restart"),
                trigger: () => root.reboot()
            });
        }

        if (root.showShutdown && root.canShutdown) {
            actions.push({
                actionId: "shutdown",
                icon: (root.customIcons && root.customIcons.shutdown) ? root.customIcons.shutdown : "power_settings_new",
                label: qsTr("Shut Down"),
                trigger: () => root.shutdown()
            });
        }

        return actions;
    }

    visible: visibleActions.length > 0

    function suspend(): void {
        root.actionTriggered("suspend");
        if (activeSessionManagement && activeSessionManagement.canSuspend) {
            try {
                activeSessionManagement.suspend();
                return;
            } catch(e) {}
        }
        sessionActionSource.connectSource("systemctl suspend 2>/dev/null");
    }

    function hibernate(): void {
        root.actionTriggered("hibernate");
        if (activeSessionManagement && activeSessionManagement.canHibernate) {
            try {
                activeSessionManagement.hibernate();
                return;
            } catch(e) {}
        }
        sessionActionSource.connectSource("systemctl hibernate 2>/dev/null");
    }

    function switchUser(): void {
        root.actionTriggered("switchUser");
        if (activeSessionManagement && activeSessionManagement.canSwitchUser) {
            try {
                activeSessionManagement.switchUser();
                return;
            } catch(e) {}
        }
        sessionActionSource.connectSource("qdbus6 org.kde.ksmserver /KSMServer org.kde.KSMServerInterface.openSwitchUser 2>/dev/null || dm-tool switch-to-greeter 2>/dev/null");
    }

    function logout(): void {
        root.actionTriggered("logout");
        if (activeSessionManagement && activeSessionManagement.canLogout) {
            try {
                activeSessionManagement.requestLogout(root.confirmationMode);
                return;
            } catch(e) {}
        }
        sessionActionSource.connectSource("qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null");
    }

    function reboot(): void {
        root.actionTriggered("reboot");
        if (activeSessionManagement && activeSessionManagement.canReboot) {
            try {
                activeSessionManagement.requestReboot(root.confirmationMode);
                return;
            } catch(e) {}
        }
        sessionActionSource.connectSource("qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot 2>/dev/null || systemctl reboot 2>/dev/null");
    }

    function shutdown(): void {
        root.actionTriggered("shutdown");
        if (activeSessionManagement && activeSessionManagement.canShutdown) {
            try {
                activeSessionManagement.requestShutdown(root.confirmationMode);
                return;
            } catch(e) {}
        }
        sessionActionSource.connectSource("qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndShutdown 2>/dev/null || systemctl poweroff 2>/dev/null");
    }

    function triggerAction(actionId: string): void {
        for (var i = 0; i < visibleActions.length; i++) {
            if (visibleActions[i].actionId === actionId) {
                visibleActions[i].trigger();
                return;
            }
        }
    }

    SessionManagement {
        id: defaultSessionManagement
    }

    Plasma5Support.DataSource {
        id: sessionActionSource
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => disconnectSource(source)
    }

    Column {
        id: contentCol
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2 * root.centerScale

        Row {
            id: actionsRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6 * root.centerScale

            Repeater {
                model: root.visibleActions

                Item {
                    id: actionBtn
                    width: Math.max(26, Math.round(32 * root.centerScale))
                    height: width

                    readonly property var actionData: modelData
                    readonly property bool isHovered: btnMouse.containsMouse

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: actionBtn.isHovered ? Qt.rgba(root.clPrimary.r, root.clPrimary.g, root.clPrimary.b, 0.12) : "transparent"
                        scale: btnMouse.pressed ? 0.88 : actionBtn.isHovered ? 1.05 : 1.0

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: actionBtn.actionData.icon
                            font.family: LockScreenConfig.fontIcon
                            font.pixelSize: Math.max(16, Math.round(20 * root.centerScale))
                            color: actionBtn.isHovered ? root.clPrimary : root.clSurfaceVariantFg

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            root.hoveredAction = actionBtn.actionData.actionId;
                            root.hoveredLabel = actionBtn.actionData.label;
                        }
                        onExited: {
                            if (root.hoveredAction === actionBtn.actionData.actionId) {
                                root.hoveredAction = "";
                                root.hoveredLabel = "";
                            }
                        }
                        onClicked: actionBtn.actionData.trigger()
                    }
                }
            }
        }

        Item {
            id: labelContainer
            width: actionsRow.width
            height: Math.max(12, Math.round(14 * root.centerScale))
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                anchors.centerIn: parent
                text: root.hoveredLabel
                font.family: LockScreenConfig.fontBody
                font.pixelSize: Math.max(10, Math.round(12 * root.centerScale))
                color: root.clPrimary
                opacity: root.hoveredLabel.length > 0 ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }
}
