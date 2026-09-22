pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit 0.1
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

StyledWindow {
    id: root

    required property PolkitAgent agent
    required property var screen

    property int activeScreenScale: 1
    readonly property real centerScale: Math.max(0.8, Math.min(1, root.height / 1440))
    readonly property int centerWidth: root.screen ? Tokens.sizes.lock.centerWidth * centerScale : 0
    readonly property int passwordMaxWidth: centerWidth * 0.8
    
    readonly property string rawMessage: agent.flow ? agent.flow.message : ""
    readonly property var splitMessage: {
        let msg = rawMessage.trim();
        let cmd = "";
        
        let pkexecMatch = msg.match(/Authentication is needed to run `(.+?)' as the super user/);
        if (pkexecMatch) {
            cmd = pkexecMatch[1];
            msg = "Root privileges are required to execute:";
        } else if (msg.includes('\n')) {
            let parts = msg.split('\n').filter(s => s.trim().length > 0);
            if (parts.length > 1) {
                cmd = parts.pop().trim();
                msg = parts.join('\n').trim();
            }
        } else if (msg.includes(': ')) {
            let lastColonIdx = msg.lastIndexOf(': ');
            cmd = msg.substring(lastColonIdx + 2).trim();
            msg = msg.substring(0, lastColonIdx + 1).trim();
        } else {
            let backtickMatch = msg.match(/`(.+?)`/);
            if (backtickMatch) {
                cmd = backtickMatch[1];
                msg = msg.replace(backtickMatch[0], "").replace(/\s+/g, " ").trim();
            }
        }
        
        return { message: msg, command: cmd };
    }
    readonly property string mainMessage: splitMessage.message
    readonly property string commandText: splitMessage.command

    property string buffer: ""
    property bool isActive: agent.isActive && agent.flow != null

    readonly property list<int> shapeQueue: {
        let shapes = [
            MaterialShape.Circle,
            MaterialShape.Square,
            MaterialShape.Diamond,
            MaterialShape.Pentagon,
            MaterialShape.Gem,
            MaterialShape.Cookie4Sided,
            MaterialShape.Cookie6Sided
        ];
        // Fisher-Yates shuffle
        for (let i = shapes.length - 1; i > 0; i--) {
            let j = Math.floor(Math.random() * (i + 1));
            [shapes[i], shapes[j]] = [shapes[j], shapes[i]];
        }
        return shapes;
    }

    name: "polkit"
    visible: isActive || closeAnim.running
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    onIsActiveChanged: {
        if (isActive) {
            closeAnim.stop()
            openAnim.start()
        } else {
            openAnim.stop()
            closeAnim.start()
        }
    }

    ParallelAnimation {
        id: openAnim

        SequentialAnimation {
            ParallelAnimation {
                Anim { target: dialogContainer; property: "opacity"; to: 1; type: Anim.FastEffects }
                Anim { target: dialogContainer; property: "scale"; to: 1; type: Anim.Emphasized }
            }
            // Delegate size expansion to Behaviors so they constantly evaluate layout recalculations
            PropertyAction { target: dialogContainer; property: "isExpanded"; value: true }
            ParallelAnimation {
                Anim { target: lockIcon; property: "scale"; to: 0; type: Anim.Emphasized }
                Anim { type: Anim.FastEffects; target: lockIcon; property: "opacity"; to: 0 }
                Anim { type: Anim.DefaultEffects; target: dialogContent; property: "opacity"; to: 1 }
                Anim { target: dialogContent; property: "scale"; to: 1; type: Anim.EmphasizedLarge }
                Anim { target: dialogBg; property: "radius"; to: Tokens.rounding.large; type: Anim.EmphasizedLarge }
            }
        }
    }

    TextMetrics {
        id: nonAnimPlaceholder

        text: qsTr("Enter your password")
        font: Tokens.font.body.builders.medium.scale(centerScale).width(110).build()
    }

    SequentialAnimation {
        id: closeAnim

        ParallelAnimation {
            // Trigger collapse logic via the Behavior state
            PropertyAction { target: dialogContainer; property: "isExpanded"; value: false }
            Anim { target: dialogBg; property: "radius"; to: dialogContainer.initialRadius }
            Anim { target: dialogContent; property: "scale"; to: 0 }
            Anim { target: dialogContent; property: "opacity"; to: 0; type: Anim.StandardSmall }
            Anim { target: lockIcon; property: "opacity"; to: 1; type: Anim.StandardLarge }
            Anim { target: lockIcon; property: "scale"; to: 1; type: Anim.StandardLarge }

            SequentialAnimation {
                PauseAnimation { duration: Tokens.anim.durations.small }
                Anim { target: dialogContainer; property: "opacity"; to: 0; type: Anim.Standard }
                PropertyAction { target: dialogContainer; property: "scale"; value: 0 }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
    }

    Item {
        id: dialogContainer

        property bool isExpanded: false

        readonly property int iconSize: lockIcon.implicitHeight + (root.screen ? Tokens.padding.large * 4 : 0)
        readonly property int initialRadius: root.screen ? iconSize / 4 * Tokens.rounding.scale : 0

        property int targetWidth: Math.max(420, root.passwordMaxWidth + Tokens.padding.extraLarge * 2)
        property int targetHeight: dialogContent.implicitHeight + (Tokens.padding.large * 2)

        anchors.centerIn: parent
        implicitWidth: isExpanded ? targetWidth : iconSize
        implicitHeight: isExpanded ? targetHeight : iconSize
        scale: 0

        // This prevents the snapshotting issue by persistently interpolating dynamically updating bindings
        Behavior on implicitWidth { Anim { type: Anim.EmphasizedLarge } }
        Behavior on implicitHeight { Anim { type: Anim.EmphasizedLarge } }

        StyledRect {
            id: dialogBg

            anchors.fill: parent
            radius: dialogContainer.initialRadius
            color: Colours.layer(Colours.palette.m3surface, 0)
            
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                blurMax: 15
                shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.7)
            }
        }

        MaterialIcon {
            id: lockIcon

            anchors.centerIn: parent
            text: "shield_person"
            fill: 1
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.Medium).build()
            color: Colours.palette.m3secondary
        }

        ColumnLayout {
            id: dialogContent

            width: dialogContainer.targetWidth - Tokens.padding.large * 2
            anchors.centerIn: parent

            opacity: 0
            scale: 0
            spacing: Tokens.spacing.large

            // Title Container
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: titleLayout.implicitHeight + Tokens.padding.large * 2
                color: Colours.layer(Colours.palette.m3surfaceContainer, 1)
                radius: Tokens.rounding.large
                
                ColumnLayout {
                    id: titleLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Authentication Required")
                        font: Tokens.font.title.builders.large.weight(Font.Medium).build()
                        color: Colours.palette.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // Message and Command
            Column {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                StyledText {
                    width: parent.width
                    text: root.mainMessage
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledRect {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.commandText.length > 0
                    width: Math.min(commandLabel.implicitWidth + Tokens.padding.large * 2, parent.width)
                    implicitHeight: commandLabel.implicitHeight + Tokens.padding.small * 2
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)
                    radius: Tokens.rounding.small
                    
                    StyledText {
                        id: commandLabel

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.small
                        anchors.leftMargin: Tokens.padding.large
                        anchors.rightMargin: Tokens.padding.large
                        text: root.commandText
                        font: Tokens.font.mono.medium
                        color: Colours.palette.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WrapAnywhere
                    }
                }

                StyledText {
                    width: parent.width
                    text: agent.flow && agent.flow.supplementaryMessage ? agent.flow.supplementaryMessage : ""
                    font: Tokens.font.body.small
                    color: agent.flow && agent.flow.supplementaryIsError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    visible: text.length > 0
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            StyledRect {
                id: passwordRect
                Layout.alignment: Qt.AlignHCenter

                implicitWidth: {
                    const emptyW = nonAnimPlaceholder.width + iconWrapper.implicitWidth + enterButton.implicitWidth + passwordInputLayout.spacing * 2 + Tokens.padding.medium * 2;
                    return root.buffer.length > 0 ? root.passwordMaxWidth : Math.min(root.passwordMaxWidth, emptyW);
                }
                implicitHeight: passwordInputLayout.implicitHeight + Tokens.padding.small
                color: Colours.layer(Colours.palette.m3surfaceContainer, 1)
                radius: Tokens.rounding.full
                
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                        if (agent.flow && root.buffer) {
                            agent.flow.submit(root.buffer)
                            root.buffer = ""
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace) {
                        if (root.buffer.length > 0) {
                            root.buffer = root.buffer.slice(0, -1);
                        }
                        if (root.buffer.length === 0) {
                            charList.implicitWidth = charList.implicitWidth;
                            placeholder.animate = true;
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        if (agent.flow) {
                            agent.flow.cancelAuthenticationRequest()
                        }
                        root.buffer = ""
                        event.accepted = true;
                    } else if (event.text.length > 0) {
                        charList.bindImWidth();
                        root.buffer += event.text;
                        placeholder.animate = false;
                        event.accepted = true;
                    }
                }

                Behavior on implicitWidth { Anim {} }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: passwordRect.forceActiveFocus()
                }

                Connections {
                    function onIsActiveChanged() {
                        if (agent.isActive) {
                            root.buffer = ""
                            passwordRect.forceActiveFocus()
                        }
                    }

                    target: agent
                }

                RowLayout {
                    id: passwordInputLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.extraSmall
                    spacing: Tokens.spacing.medium
                    
                    Item {
                        id: iconWrapper
                        Layout.fillHeight: true

                        implicitWidth: height
                        
                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "lock"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.builders.medium.scale(centerScale).build()
                        }
                    }
                    
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        StyledText {
                            id: placeholder

                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: Centering.pixelAlign(parent.height, height)
                            text: nonAnimPlaceholder.text
                            animate: true
                            color: Colours.palette.m3onSurfaceVariant
                            font: nonAnimPlaceholder.font
                            opacity: root.buffer ? 0 : 1

                            Behavior on opacity { Anim { type: Anim.DefaultEffects } }
                        }

                        AnimatedPasswordMask {
                            id: charList

                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: implicitWidth > parent.width ? -(implicitWidth - parent.width) / 2 : 0
                            buffer: root.buffer
                            shapeQueue: root.shapeQueue
                        }
                    }
                    
                    Item {
                        id: enterButton

                        implicitWidth: implicitHeight
                        implicitHeight: {
                            const h = enterIcon.implicitHeight + Tokens.padding.extraSmall * 2;
                            return h % 2 === 0 ? h : h + 1;
                        }

                        MaterialShape {
                            anchors.fill: parent
                            color: root.buffer ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                            shape: root.buffer ? MaterialShape.Arrow : MaterialShape.Circle
                            scale: !root.buffer ? 1 : enterMouse.pressed ? 0.6 : enterMouse.containsMouse ? 0.8 : 0.7
                            rotation: 90
                            
                            Behavior on scale { Anim { type: Anim.FastSpatial } }
                            Behavior on color { CAnim {} }
                            
                            MouseArea {
                                id: enterMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.buffer ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (agent.flow && root.buffer) {
                                        agent.flow.submit(root.buffer)
                                        root.buffer = ""
                                    }
                                }
                            }
                        }

                        MaterialIcon {
                            id: enterIcon

                            anchors.centerIn: parent
                            text: "arrow_forward"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.builders.medium.scale(centerScale * 1.2).build()
                            opacity: root.buffer ? 0 : 1

                            Behavior on opacity { Anim { type: Anim.DefaultEffects } }
                        }
                    }
                }
            }
        }
    }
}