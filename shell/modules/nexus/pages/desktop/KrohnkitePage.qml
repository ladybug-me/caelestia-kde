pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property bool showLogout: false

    title: qsTr("Window Tiling")
    isSubPage: true


    property list<MenuItem> layoutItems: [
        MenuItem { text: qsTr("BTree"); visible: KrohnkiteConfig.binaryTreeLayoutEnabled },
        MenuItem { text: qsTr("Monocle"); visible: KrohnkiteConfig.monocleLayoutEnabled },
        MenuItem { text: qsTr("Floating"); visible: KrohnkiteConfig.floatingLayoutEnabled },
        MenuItem { text: qsTr("Quarter"); visible: KrohnkiteConfig.quarterLayoutEnabled },
        MenuItem { text: qsTr("Spread"); visible: KrohnkiteConfig.spreadLayoutEnabled },
        MenuItem { text: qsTr("Stacked"); visible: KrohnkiteConfig.stackedLayoutEnabled },
        MenuItem { text: qsTr("Stair"); visible: KrohnkiteConfig.stairLayoutEnabled },
        MenuItem { text: qsTr("Columns"); visible: KrohnkiteConfig.columnsLayoutEnabled },
        MenuItem { text: qsTr("Three Column"); visible: KrohnkiteConfig.threeColumnLayoutEnabled },
        MenuItem { text: qsTr("Spiral"); visible: KrohnkiteConfig.spiralLayoutEnabled },
        MenuItem { text: qsTr("Tile"); visible: KrohnkiteConfig.tileLayoutEnabled }
    ]

    property list<string> layoutValues: [
        "BTree", "Monocle", "Floating", "Quarter", "Spread",
        "Stacked", "Stair", "Columns", "ThreeColumn", "Spiral", "Tile"
    ]

    headerActions: [
        IconTextButton {
            text: qsTr("Save Changes")
            icon: "check"
            type: TextButton.Filled
            onClicked: {
                KrohnkiteConfig.apply()
                showLogout = true;
            }
        },
        IconTextButton {
            visible: showLogout
            text: qsTr("Logout to Apply Changes")
            icon: "logout"
            type: TextButton.Filled
            onClicked: restartProcess.running = true
            
            Process {
                id: restartProcess

                command: ["bash", "-c", "nohup bash -c 'qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null || true' >/dev/null 2>&1"]
            }
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Window Tiling")
            subtext: qsTr("Automatically tile windows using Krohnkite")
            checked: Config.general.krohnkiteEnabled
            onToggled: {
                GlobalConfig.general.krohnkiteEnabled = checked;
                GlobalConfig.save();
                showLogout = true;
                Quickshell.execDetached(["bash", "-c", `
                    if [[ "${checked ? 'true' : 'false'}" == "true" ]]; then
                        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "krohnkite" 2>/dev/null || true
                        if ! kpackagetool6 -t KWin/Script -s krohnkite >/dev/null 2>&1; then
                            if command -v kpackagetool6 >/dev/null 2>&1; then
                                notify-send "Installing Krohnkite..." "Please stay connected to the internet..."
                                tmpdir="$(mktemp -d)"
                                kwinscript_url="$(curl -sL https://codeberg.org/api/v1/repos/anametologin/Krohnkite/releases/latest | grep -oP '"browser_download_url":\\s*"\\K[^"]+\\.kwinscript' | head -1)"
                                if [[ -n "$kwinscript_url" ]] && curl -sL "$kwinscript_url" -o "$tmpdir/krohnkite.kwinscript"; then
                                    kpackagetool6 -t KWin/Script -i "$tmpdir/krohnkite.kwinscript" 2>/dev/null || true
                                    notify-send "Installation Completed..." "Krohnkite has been installed successfully..."
                                else
                                    notify-send "Installation Failed..." "Krohnkite could not be downloaded. Please try again..."
                                fi
                                rm -rf "$tmpdir"
                            fi
                        fi
                        kwriteconfig6 --file kwinrc --group "Plugins" --key "krohnkiteEnabled" "true" 2>/dev/null || true
                        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
                    else
                        qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "KrohnkiteFloatAll" 2>/dev/null || true
                        sleep 0.1
                        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "krohnkite" 2>/dev/null || true
                        kwriteconfig6 --file kwinrc --group "Plugins" --key "krohnkiteEnabled" "false" 2>/dev/null || true
                        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
                    fi
                `]);
            }
        }

        SelectRow {
            last: true
            label: qsTr("Switch Layout")
            subtext: qsTr("Triggers the KWin shortcut to switch layout")
            menuItems: root.layoutItems
            active: {
                let idx = root.layoutValues.indexOf(Config.general.krohnkiteLastLayout);
                return idx >= 0 ? root.layoutItems[idx] : null;
            }
            fallbackText: qsTr("Select Layout...")
            fallbackIcon: "dashboard"
            onSelected: item => {
                let layoutName = root.layoutValues[root.layoutItems.indexOf(item)];
                GlobalConfig.general.krohnkiteLastLayout = layoutName;
                GlobalConfig.save();
                Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "Krohnkite" + layoutName + "Layout"]);
            }
        }

        KrohnkitePreview {
            Layout.fillWidth: true
            layout: Config.general.krohnkiteLastLayout
            gapBetween: KrohnkiteConfig.screenGapBetween
            gapTop: KrohnkiteConfig.screenGapTop
            gapBottom: KrohnkiteConfig.screenGapBottom
            gapLeft: KrohnkiteConfig.screenGapLeft
            gapRight: KrohnkiteConfig.screenGapRight
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium

            SectionHeader {
                Layout.fillWidth: true
                Layout.topMargin: 0
                text: qsTr("Gaps")
                first: true
            }

            IconButton {
                icon: "settings_backup_restore"
                type: IconButton.Text
                Layout.alignment: Qt.AlignBottom
                onClicked: {
                    KrohnkiteConfig.screenGapBetween = 4
                    KrohnkiteConfig.screenGapTop = 4
                    KrohnkiteConfig.screenGapBottom = 4
                    KrohnkiteConfig.screenGapLeft = 4
                    KrohnkiteConfig.screenGapRight = 4
                }
            }
        }

        StepperRow {
            first: true
            label: qsTr("Gap Between Windows")
            subtext: qsTr("Space between tiled windows")
            from: 0
            to: 80
            value: KrohnkiteConfig.screenGapBetween
            onMoved: v => KrohnkiteConfig.screenGapBetween = v
        }

        StepperRow {
            label: qsTr("Top Gap")
            subtext: qsTr("Distance from the top screen edge")
            from: 0
            to: 80
            value: KrohnkiteConfig.screenGapTop
            onMoved: v => KrohnkiteConfig.screenGapTop = v
        }

        StepperRow {
            label: qsTr("Bottom Gap")
            subtext: qsTr("Distance from the bottom screen edge")
            from: 0
            to: 80
            value: KrohnkiteConfig.screenGapBottom
            onMoved: v => KrohnkiteConfig.screenGapBottom = v
        }

        StepperRow {
            label: qsTr("Left Gap")
            subtext: qsTr("Distance from the left screen edge")
            from: 0
            to: 80
            value: KrohnkiteConfig.screenGapLeft
            onMoved: v => KrohnkiteConfig.screenGapLeft = v
        }

        StepperRow {
            last: true
            label: qsTr("Right Gap")
            subtext: qsTr("Distance from the right screen edge")
            from: 0
            to: 80
            value: KrohnkiteConfig.screenGapRight
            onMoved: v => KrohnkiteConfig.screenGapRight = v
        }

        SectionHeader {
            Layout.topMargin: Tokens.spacing.medium
            text: qsTr("Ignored Window Classes")
        }

        ConnectedRect {
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: colLayout.implicitHeight + colLayout.anchors.margins * 2

            ColumnLayout {
                id: colLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Window Classes")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Comma separated list of classes to not tile (e.g. quickshell,krunner)")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Layout.topMargin: Tokens.spacing.small
                    radius: Tokens.rounding.small
                    color: Colours.layer(Colours.palette.m3surfaceVariant, 2)

                    StyledTextField {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colours.palette.m3onSurface
                        placeholderText: "krunner,yakuake,spectacle..."
                        text: KrohnkiteConfig.ignoreClass
                        onAccepted: KrohnkiteConfig.ignoreClass = text
                    }
                }
            }
        }

        SectionHeader {
            Layout.topMargin: Tokens.spacing.medium
            text: qsTr("Enabled Layouts")
        }

        ToggleRow {
            first: true
            text: qsTr("Binary Tree")
            subtext: qsTr("Splits the screen in half recursively")
            checked: KrohnkiteConfig.binaryTreeLayoutEnabled
            onToggled: KrohnkiteConfig.binaryTreeLayoutEnabled = checked
        }

        ToggleRow {
            text: qsTr("Floating")
            subtext: qsTr("Windows are placed freely, without tiling")
            checked: KrohnkiteConfig.floatingLayoutEnabled
            onToggled: KrohnkiteConfig.floatingLayoutEnabled = checked
        }

        ToggleRow {
            text: qsTr("Monocle")
            subtext: qsTr("Displays one window maximized at a time")
            checked: KrohnkiteConfig.monocleLayoutEnabled
            onToggled: KrohnkiteConfig.monocleLayoutEnabled = checked
        }

        ToggleRow {
            text: qsTr("Quarter")
            subtext: qsTr("Tiles windows into four equal quarters")
            checked: KrohnkiteConfig.quarterLayoutEnabled
            onToggled: KrohnkiteConfig.quarterLayoutEnabled = checked
        }

        ToggleRow {
            text: qsTr("Spiral")
            subtext: qsTr("Tiles windows in an inward-spiraling pattern")
            checked: KrohnkiteConfig.spiralLayoutEnabled
            onToggled: KrohnkiteConfig.spiralLayoutEnabled = checked
        }

        ToggleRow {
            text: qsTr("Spread")
            subtext: qsTr("Evenly spreads all windows across the screen")
            checked: KrohnkiteConfig.spreadLayoutEnabled
            onToggled: KrohnkiteConfig.spreadLayoutEnabled = checked
        }

        ToggleRow {
            text: qsTr("Stacked")
            subtext: qsTr("One main window with the rest stacked below or beside")
            checked: KrohnkiteConfig.stackedLayoutEnabled
            onToggled: KrohnkiteConfig.stackedLayoutEnabled = checked
        }

        ToggleRow {
            text: qsTr("Stair")
            subtext: qsTr("Tiles windows descending like a staircase")
            checked: KrohnkiteConfig.stairLayoutEnabled
            onToggled: KrohnkiteConfig.stairLayoutEnabled = checked
        }

        ToggleRow {
            text: qsTr("Three Column")
            subtext: qsTr("Splits the screen into three vertical columns")
            checked: KrohnkiteConfig.threeColumnLayoutEnabled
            onToggled: KrohnkiteConfig.threeColumnLayoutEnabled = checked
        }

        ToggleRow {
            text: qsTr("Tile")
            subtext: qsTr("Standard master and stack tiling layout")
            checked: KrohnkiteConfig.tileLayoutEnabled
            onToggled: KrohnkiteConfig.tileLayoutEnabled = checked
        }
        
        ToggleRow {
            text: qsTr("Cascade")
            subtext: qsTr("Windows overlap sequentially like a waterfall")
            checked: KrohnkiteConfig.cascadeLayoutEnabled
            onToggled: KrohnkiteConfig.cascadeLayoutEnabled = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Columns")
            subtext: qsTr("Splits the screen into equal vertical columns")
            checked: KrohnkiteConfig.columnsLayoutEnabled
            onToggled: KrohnkiteConfig.columnsLayoutEnabled = checked
        }
    }
}
