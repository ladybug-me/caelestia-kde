pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Per Element Scaling Offset")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            last: !GlobalConfig.bar.perElementPreviewScale && !GlobalConfig.bar.perElementFontScale
            text: qsTr("Enable per-element offsets")
            subtext: qsTr("Customize preview scale and font for each popout type")
            checked: GlobalConfig.bar.perElementPreviewScale || GlobalConfig.bar.perElementFontScale
            onToggled: {
                GlobalConfig.bar.perElementPreviewScale = checked;
                GlobalConfig.bar.perElementFontScale = checked;
            }
            // Custom reset: turns both per-element flags off together
            reset: ({
                customGet: () => GlobalConfig.bar.perElementPreviewScale || GlobalConfig.bar.perElementFontScale,
                customDef: false,
                customSet: v => {
                    GlobalConfig.bar.perElementPreviewScale = v;
                    GlobalConfig.bar.perElementFontScale = v;
                }
            })
        }

        ColumnLayout {
            id: scalesCol

            Layout.fillWidth: true
            visible: GlobalConfig.bar.perElementPreviewScale || GlobalConfig.bar.perElementFontScale
            spacing: Tokens.spacing.extraSmall / 2

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.padding.medium
                Layout.leftMargin: Tokens.padding.largeIncreased
                Layout.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                TextButton {
                    text: qsTr("RESET ALL")
                    type: TextButton.Filled
                    ToolTip.text: qsTr("Reset all to 0")
                    ToolTip.visible: hovered
                    onClicked: {
                        const keys = ["greeter", "audio", "battery", "bluetooth", "clock", "dock", "github", "lockStatus", "network", "notifications", "peripheralBattery", "trayMenu", "wirelessPassword"];
                        for (let k of keys) {
                            GlobalConfig.bar.previewScales[k] = 0.0;
                            GlobalConfig.bar.previewFontScales[k] = 0.0;
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                id: headerCols

                // Same column geometry as every row, derived from the container
                // width (not from this row's own width, which never stretches):
                // 30% label share, then the two value columns split what's left
                // once the reset widths are reserved
                readonly property real rowWidth: scalesCol.width - Layout.leftMargin - Layout.rightMargin
                readonly property real labelShare: Math.round(headerCols.rowWidth * 0.3)
                readonly property real colWidth: Math.max(0, (headerCols.rowWidth - labelShare - Tokens.spacing.extraSmall * 4 - headerResetProbe.implicitWidth * 2) / 2)
                // CustomSpinBox puts a 62px value field before the slider, so the
                // slider track centre sits half of that inset right of the column
                // centre; the titles shift by the same amount to sit over it
                readonly property real knobShift: 62 + Tokens.spacing.small

                Layout.fillWidth: true
                Layout.preferredWidth: headerCols.rowWidth
                Layout.topMargin: Tokens.spacing.small
                Layout.bottomMargin: Tokens.padding.small
                Layout.leftMargin: Tokens.padding.largeIncreased
                Layout.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.extraSmall

                Item {
                    Layout.preferredWidth: headerCols.labelShare
                }

                StyledText {
                    id: scaleTitle

                    text: qsTr("Scale")
                    font: Tokens.font.label.large
                    Layout.leftMargin: headerCols.knobShift
                    Layout.preferredWidth: headerCols.colWidth - headerCols.knobShift
                    horizontalAlignment: Text.AlignHCenter
                }

                Item {
                    // Reserves the width of a row's reset button so the header stays aligned
                    Layout.preferredWidth: headerResetProbe.implicitWidth
                }

                StyledText {
                    id: fontTitle

                    text: qsTr("Font")
                    font: Tokens.font.label.large
                    Layout.leftMargin: headerCols.knobShift
                    Layout.preferredWidth: headerCols.colWidth - headerCols.knobShift
                    horizontalAlignment: Text.AlignHCenter
                }

                Item {
                    Layout.preferredWidth: headerResetProbe.implicitWidth
                }

                SettingResetButton {
                    id: headerResetProbe

                    // Invisible probe: only used to measure the reset button width
                    options: null
                }
            }

            DoubleStepperRow {
                first: true
                last: false
                label: qsTr("Greeter")
                resetKey: "greeter"
                
                scaleValue: GlobalConfig.bar.previewScales.greeter
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.greeter = v
                
                fontValue: GlobalConfig.bar.previewFontScales.greeter
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.greeter = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Audio")
                resetKey: "audio"
                
                scaleValue: GlobalConfig.bar.previewScales.audio
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.audio = v
                
                fontValue: GlobalConfig.bar.previewFontScales.audio
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.audio = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Battery")
                resetKey: "battery"
                
                scaleValue: GlobalConfig.bar.previewScales.battery
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.battery = v
                
                fontValue: GlobalConfig.bar.previewFontScales.battery
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.battery = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Bluetooth")
                resetKey: "bluetooth"
                
                scaleValue: GlobalConfig.bar.previewScales.bluetooth
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.bluetooth = v
                
                fontValue: GlobalConfig.bar.previewFontScales.bluetooth
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.bluetooth = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Clock")
                resetKey: "clock"
                
                scaleValue: GlobalConfig.bar.previewScales.clock
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.clock = v
                
                fontValue: GlobalConfig.bar.previewFontScales.clock
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.clock = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Dock")
                resetKey: "dock"
                
                scaleValue: GlobalConfig.bar.previewScales.dock
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.dock = v
                
                fontValue: GlobalConfig.bar.previewFontScales.dock
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.dock = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("GitHub")
                resetKey: "github"
                
                scaleValue: GlobalConfig.bar.previewScales.github
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.github = v
                
                fontValue: GlobalConfig.bar.previewFontScales.github
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.github = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Lock status")
                resetKey: "lockStatus"
                
                scaleValue: GlobalConfig.bar.previewScales.lockStatus
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.lockStatus = v
                
                fontValue: GlobalConfig.bar.previewFontScales.lockStatus
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.lockStatus = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Network")
                resetKey: "network"
                
                scaleValue: GlobalConfig.bar.previewScales.network
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.network = v
                
                fontValue: GlobalConfig.bar.previewFontScales.network
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.network = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Notifications")
                resetKey: "notifications"
                
                scaleValue: GlobalConfig.bar.previewScales.notifications
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.notifications = v
                
                fontValue: GlobalConfig.bar.previewFontScales.notifications
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.notifications = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Peripheral battery")
                resetKey: "peripheralBattery"
                
                scaleValue: GlobalConfig.bar.previewScales.peripheralBattery
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.peripheralBattery = v
                
                fontValue: GlobalConfig.bar.previewFontScales.peripheralBattery
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.peripheralBattery = v
            }
            DoubleStepperRow {
                first: false
                last: false
                label: qsTr("Tray menu")
                resetKey: "trayMenu"
                
                scaleValue: GlobalConfig.bar.previewScales.trayMenu
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.trayMenu = v
                
                fontValue: GlobalConfig.bar.previewFontScales.trayMenu
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.trayMenu = v
            }
            DoubleStepperRow {
                first: false
                last: true
                label: qsTr("Wireless password")
                resetKey: "wirelessPassword"
                
                scaleValue: GlobalConfig.bar.previewScales.wirelessPassword
                scaleFrom: -1.0; scaleTo: 1.0; scaleStepSize: 0.05
                onScaleMoved: v => GlobalConfig.bar.previewScales.wirelessPassword = v
                
                fontValue: GlobalConfig.bar.previewFontScales.wirelessPassword
                fontFrom: -1.0; fontTo: 1.0; fontStepSize: 0.05
                onFontMoved: v => GlobalConfig.bar.previewFontScales.wirelessPassword = v
            }
        }
    }
}
