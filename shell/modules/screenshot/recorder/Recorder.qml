pragma ComponentBehavior: Bound

import ".."
import "../../../components"
import "../../../components/controls"
import "../../../utils"
import "../../../services"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services

Variants {
    model: Screens.screens
    
    PanelWindow {
        id: root

        required property ShellScreen modelData

        screen: modelData

        property bool active: false
        
        Connections {
            target: Visibilities.getForActive()

            function onScreenshotChanged() {
                root.active = Visibilities.getForActive().screenshot;
            }
        }
        
        onActiveChanged: {
            if (!active) visible = false;
            else visible = true;
        }

        visible: false

        color: "transparent"

        mask: Region {}

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.namespace: "osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Rectangle {
            id: bg

            color: Colours.palette.m3scrim
            opacity: root.active ? 0.3 : 0
            anchors.fill: parent
            
            MouseArea {
                anchors.fill: parent
                onClicked: Visibilities.getForActive().screenshot = false
            }
            
            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Rectangle {
            id: panel

            anchors.centerIn: parent
            color: Colours.palette.m3surface
            radius: Tokens.rounding.large

            opacity: root.active ? 1 : 0
            scale: root.active ? 1 : 0.9

            implicitWidth: layout.implicitWidth + Tokens.padding.extraLarge * 2
            implicitHeight: layout.implicitHeight + Tokens.padding.extraLarge * 2

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            ColumnLayout {
                id: layout

                anchors.centerIn: parent
                spacing: Tokens.spacing.medium

                Row {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    spacing: Tokens.spacing.medium

                    BigRecorderButton {
                        materialSymbol: "screenshot_region"
                        name: qsTr("Screenshot region")
                        onClicked: {
                            Visibilities.getForActive().screenshot = false;
                            Launch.exec(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
                        }
                    }

                    BigRecorderButton {
                        materialSymbol: "photo_camera"
                        name: qsTr("Screenshot")
                        onClicked: {
                            Visibilities.getForActive().screenshot = false;
                            Launch.exec(["bash", "-c", "spectacle -b -n -f -c 2>/dev/null || " +
                                "import -window root " + Paths.runtimeTemp("fullshot.png") + " && wl-copy < " + Paths.runtimeTemp("fullshot.png")]);
                        }
                    }

                    BigRecorderButton {
                        materialSymbol: "screen_record"
                        name: qsTr("Record region")
                        onClicked: {
                            Visibilities.getForActive().screenshot = false;
                            Launch.exec(["spectacle", "-R", "r"]);
                        }
                    }
                    
                    BigRecorderButton {
                        materialSymbol: "capture"
                        name: qsTr("Record screen")
                        onClicked: {
                            Visibilities.getForActive().screenshot = false;
                            Launch.exec(["spectacle", "-R", "s"]);
                        }
                    }
                }

                IconTextButton {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    type: ButtonBase.Tonal
                    icon: "animated_images"
                    text: qsTr("Open recordings folder")
                    
                    inactiveColour: Colours.palette.m3surfaceContainerHigh
                    activeColour: Colours.palette.m3surfaceContainerHighest
                    inactiveOnColour: Colours.palette.m3onSurface
                    activeOnColour: Colours.palette.m3onSurface

                    onClicked: {
                        Visibilities.getForActive().screenshot = false;
                        Qt.openUrlExternally(`file://${Paths.recsdir}`);
                    }
                }
            }
        }

        component BigRecorderButton: IconButton {
            id: bigButton

            required property string materialSymbol
            required property string name
            
            type: ButtonBase.Tonal
            isRound: true
            
            inactiveColour: Colours.palette.m3surfaceContainerHigh
            activeColour: Colours.palette.m3surfaceContainerHighest
            inactiveOnColour: Colours.palette.m3onSurface
            activeOnColour: Colours.palette.m3onSurface

            implicitHeight: 66
            implicitWidth: 66

            icon: bigButton.materialSymbol

            Tooltip {
                target: bigButton
                text: bigButton.name
            }
        }
    }
}
