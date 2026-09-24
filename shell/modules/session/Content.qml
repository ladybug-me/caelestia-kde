pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Column {
    id: root

    required property DrawerVisibilities visibilities

    padding: Tokens.padding.large
    rightPadding: CUtils.clamp(padding - Config.border.thickness, 0, padding)
    spacing: Tokens.spacing.large

    SessionButton {
        id: logout

        icon: Config.session.icons.logout
        command: ["sh", "-c", "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null"]

        KeyNavigation.down: shutdown

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.visibilities.launcher)
                    logout.forceActiveFocus();
            }

            target: root.visibilities
        }
    }

    SessionButton {
        id: shutdown

        icon: Config.session.icons.shutdown
        command: Config.session.commands.shutdown

        KeyNavigation.up: logout
        KeyNavigation.down: hibernate
    }

    Item {
        width: Tokens.sizes.session.button
        height: Tokens.sizes.session.button

        AnimatedImage {
            anchors.fill: parent
            sourceSize.width: width * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
            playing: visible
            asynchronous: true
            speed: Config.general.sessionGifSpeed
            source: Paths.absolutePath(Config.paths.sessionGif)
            fillMode: AnimatedImage.PreserveAspectFit
            opacity: GlobalConfig.general.caelestiaMode ? 0 : 1

            Behavior on opacity { Anim { type: Anim.Standard } }

            visible: Config.paths.sessionGif !== ""
        }

        AnimatedImage {
            anchors.fill: parent
            sourceSize.width: width * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
            playing: visible
            asynchronous: true
            speed: Config.general.sessionGifSpeed
            source: Paths.absolutePath("root:/assets/dino.gif")
            fillMode: AnimatedImage.PreserveAspectFit
            opacity: GlobalConfig.general.caelestiaMode ? 1 : 0

            Behavior on opacity { Anim { type: Anim.Standard } }
            
            layer.enabled: true

            layer.effect: Colouriser {
                colorizationColor: Colours.palette.m3onSurface
                sourceColor: "white"
            }
        }

        AnimatedImage {
            anchors.fill: parent
            sourceSize.width: width * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
            playing: visible
            asynchronous: true
            speed: Config.general.sessionGifSpeed
            source: Paths.absolutePath("root:/assets/dino.gif")
            fillMode: AnimatedImage.PreserveAspectFit
            opacity: GlobalConfig.general.caelestiaMode ? 1 : 0

            Behavior on opacity { Anim { type: Anim.Standard } }
            
            layer.enabled: true

            layer.effect: Colouriser {
                colorizationColor: Colours.palette.m3onSurface
                sourceColor: "white"
            }
        }
    }

    SessionButton {
        id: hibernate

        icon: Config.session.icons.hibernate
        command: Config.session.commands.hibernate

        KeyNavigation.up: shutdown
        KeyNavigation.down: reboot
    }

    SessionButton {
        id: reboot

        icon: Config.session.icons.reboot
        command: Config.session.commands.reboot

        KeyNavigation.up: hibernate
    }

    component SessionButton: IconButton {
        id: button

        required property list<string> command

        function exec(): void {
            if (!SessionManager.exec(command))
                Launch.exec(command);
        }

        implicitWidth: Tokens.sizes.session.button
        implicitHeight: Tokens.sizes.session.button

        inactiveColour: activeFocus ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        inactiveOnColour: activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        radius: pressed ? Tokens.rounding.medium : activeFocus ? Tokens.rounding.extraLarge : Tokens.rounding.largeIncreased
        font: Tokens.font.icon.builders.large.scale(1.3).build()
        onClicked: exec()

        Keys.onEnterPressed: exec()
        Keys.onReturnPressed: exec()
        Keys.onEscapePressed: root.visibilities.session = false
        Keys.onPressed: event => {
            if (!Config.session.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if ((event.key === Qt.Key_J || event.key === Qt.Key_N) && KeyNavigation.down) {
                    KeyNavigation.down.focus = true;
                    event.accepted = true;
                } else if ((event.key === Qt.Key_K || event.key === Qt.Key_P) && KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab && KeyNavigation.down) {
                KeyNavigation.down.focus = true;
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                if (KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            }
        }
    }
}
