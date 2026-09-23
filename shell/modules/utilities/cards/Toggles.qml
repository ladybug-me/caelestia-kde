pragma ComponentBehavior: Bound

import "../../background"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.bar.popouts as BarPopouts

StyledRect {
    id: root

    required property DrawerVisibilities visibilities
    required property BarPopouts.Wrapper popouts

    readonly property var quickToggles: {
        const configToggles = Config.utilities.quickToggles || [];
        const disabledIds = new Set(configToggles.filter(t => t.enabled === false).map(t => t.id));

        const builtIn = [
            {
                id: "hotspot"
            },
            {
                id: "restartShell"
            },
            {
                id: "badapple"
            },
            {
                id: "pauseWallpaper"
            },
            {
                id: "nightlight"
            },
            {
                id: "easyeffects"
            }
        ].filter(t => !disabledIds.has(t.id));

        const allToggles = [...configToggles.filter(t => !disabledIds.has(t.id)), ...builtIn];
        const seenIds = new Set();

        return allToggles.filter(item => {
            if (seenIds.has(item.id))
                return false;
            seenIds.add(item.id);

            if (item.id === "vpn") {
                return GlobalConfig.utilities.vpn.selectedProvider.length > 0;
            }

            // Only a wireless device that can run an access point gets a hotspot
            // button; there is nothing to switch on anywhere else.
            if (item.id === "hotspot") {
                return Nmcli.hotspotSupported;
            }

            // Nothing to toggle if it is not installed, and a dead button is
            // worse than no button.
            if (item.id === "easyeffects") {
                return EasyEffects.available;
            }

            return true;
        });
    }

    readonly property int splitIndex: Math.ceil(quickToggles.length / 2)
    readonly property bool needExtraRow: quickToggles.length > 6

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Tokens.padding.extraLargeIncreased

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    Timer {
        id: execTimer

        interval: 250
        repeat: false

        property var pendingAction: null
        onTriggered: {
            if (pendingAction) pendingAction();
            pendingAction = null;
        }
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledText {
            text: qsTr("Quick Toggles")
            font: Tokens.font.body.medium
        }

        QuickToggleRow {
            model: root.needExtraRow ? root.quickToggles.slice(0, root.splitIndex) : root.quickToggles
        }

        QuickToggleRow {
            visible: root.needExtraRow
            model: root.needExtraRow ? root.quickToggles.slice(root.splitIndex) : []
        }
    }

    component QuickToggleRow: ButtonRow {
        property alias model: repeater.model

        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            id: repeater

            delegate: DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "wifi"
                    delegate: Toggle {
                        icon: "wifi"
                        checked: Nmcli.wifiEnabled
                        onClicked: Nmcli.toggleWifi()
                    }
                }
                DelegateChoice {
                    roleValue: "hotspot"
                    delegate: Toggle {
                        icon: "wifi_tethering"
                        checked: Nmcli.hotspotEnabled
                        onClicked: {
                            Nmcli.toggleHotspot();
                            // The tile lights on the tap. Re-reading the backend
                            // hands the light back to it, so a start that fails or
                            // is refused does not leave the tile on.
                            internalChecked = Nmcli.hotspotEnabled;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    delegate: Toggle {
                        icon: "bluetooth"
                        checked: Bluetooth.defaultAdapter?.enabled ?? false // qmllint disable unresolved-type
                        onClicked: {
                            const adapter = Bluetooth.defaultAdapter; // qmllint disable unresolved-type
                            if (adapter)
                                adapter.enabled = !adapter.enabled;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "mic"
                    delegate: Toggle {
                        icon: "mic"
                        checked: !Audio.sourceMuted
                        onClicked: {
                            const audio = Audio.source?.audio;
                            if (audio)
                                audio.muted = !audio.muted;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "settings"
                    delegate: Toggle {
                        icon: "settings"
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        isToggle: false
                        onClicked: {
                            root.visibilities.utilities = false;
                            execTimer.pendingAction = () => WindowFactory.create();
                            execTimer.restart();
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "colorpicker"
                    delegate: Toggle {
                        icon: "colorize"
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        isToggle: false
                        onClicked: {
                            root.visibilities.utilities = false;
                            execTimer.pendingAction = () => ColorPicker.pickColor();
                            execTimer.restart();
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "gameMode"
                    delegate: Toggle {
                        icon: "gamepad"
                        checked: GameMode.enabled
                        onClicked: GameMode.enabled = !GameMode.enabled
                    }
                }
                DelegateChoice {
                    roleValue: "dnd"
                    delegate: Toggle {
                        icon: "notifications_off"
                        checked: Notifs.dnd
                        onClicked: Notifs.dnd = !Notifs.dnd
                    }
                }
                DelegateChoice {
                    roleValue: "vpn"
                    delegate: Toggle {
                        icon: "vpn_key"
                        checked: VPN.connected && VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        enabled: !VPN.connecting && !VPN.disconnecting
                        isToggle: VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        onClicked: VPN.toggle()
                    }
                }
                DelegateChoice {
                    roleValue: "badapple"
                    delegate: Toggle {
                        icon: "nutrition"
                        isToggle: false
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        onClicked: {
                            if (BadApplePlayer.shouldPlay)
                                BadApplePlayer.stop();
                            else
                                BadApplePlayer.play();
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "wallpaper"
                    delegate: Toggle {
                        icon: "wallpaper"
                        isToggle: false
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        onClicked: {
                            Visibilities.launcherInitialSearch = `${GlobalConfig.launcher.actionPrefix}wallpaper `;
                            const visibilities = Visibilities.getForActive();
                            visibilities.launcher = true;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "restartShell"
                    delegate: Toggle {
                        icon: "restart_alt"
                        isToggle: false
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        onClicked: {
                            Launch.exec(["bash", "-c", `bash "${Quickshell.shellPath("scripts/restart_shell.sh")}"`]);
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "pauseWallpaper"
                    delegate: Toggle {
                        id: pauseWallpaperToggle

                        icon: "pause"
                        isToggle: true

                        Component.onCompleted: checked = Qt.binding(() => GlobalConfig.background.videoWallpaperPaused)
                        onClicked: {
                            const newVal = !GlobalConfig.background.videoWallpaperPaused;
                            GlobalConfig.background.videoWallpaperPaused = newVal;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "easyeffects"
                    delegate: Toggle {
                        checked: EasyEffects.active
                        icon: "graphic_eq"
                        onClicked: EasyEffects.toggle()

                        // Right-click opens the application itself. Toggling the
                        // service on is only half of what people want from
                        // EasyEffects -- the other half is changing what it does,
                        // and that lives in its own window.
                        //
                        // Only the right button is accepted here, so the left one
                        // falls through to the button underneath and keeps working
                        // as the toggle. Adding a second signal to ButtonBase would
                        // have reached every button in the shell for the sake of
                        // one.
                        MouseArea {
                            acceptedButtons: Qt.RightButton
                            anchors.fill: parent
                            onClicked: {
                                EasyEffects.open();
                                root.visibilities.utilities = false;
                            }
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "nightlight"
                    delegate: Toggle {
                        icon: "bedtime"
                        checked: HyprSunset.active
                        onClicked: {
                            HyprSunset.toggleNightLight();
                        }
                    }
                }
            }
        }
    }

    component Toggle: IconButton {
        inactiveColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
        fillWidth: true
        isToggle: true
        isRound: true
        shapeMorph: true
    }
}
