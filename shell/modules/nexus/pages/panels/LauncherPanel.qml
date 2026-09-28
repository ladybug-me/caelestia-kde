pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Launcher")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("General")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            checked: Config.launcher.enabled
            onToggled: GlobalConfig.launcher.enabled = checked
        }

        ToggleRow {
            text: qsTr("Use alternative logo")
            subtext: qsTr("Use the Caelestia logo or a custom image instead of your distribution's logo")
            checked: GlobalConfig.general.logo !== ""
            onToggled: {
                if (checked) {
                    if (GlobalConfig.general.logo === "") {
                        GlobalConfig.general.logo = "caelestia";
                    }
                } else {
                    GlobalConfig.general.logo = "";
                }
            }
        }

        NavRow {
            visible: GlobalConfig.general.logo !== ""
            icon: "image"
            label: qsTr("Pick custom logo")
            status: GlobalConfig.general.logo.includes("/") ? GlobalConfig.general.logo : qsTr("Select an image from your local files")
            onClicked: customLogoDialog.open()

            FileDialog {
                id: customLogoDialog

                title: qsTr("Select a custom logo")
                filterLabel: qsTr("Image files")
                filters: Images.validImageExtensions
                onAccepted: path => {
                    GlobalConfig.general.logo = path;
                }
            }
        }

        NavRow {
            visible: GlobalConfig.general.logo !== ""
            icon: "palette"
            label: qsTr("Select KDE icon")
            status: GlobalConfig.general.logo && GlobalConfig.general.logo !== "caelestia" && !GlobalConfig.general.logo.includes("/") ? GlobalConfig.general.logo : qsTr("Pick an icon from your system theme")
            onClicked: kdeIconProcess.running = true

            Process {
                id: kdeIconProcess

                command: ["kdialog", "--geticon", "Select Icon"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let res = text.trim();
                        if (res) {
                            GlobalConfig.general.logo = res;
                        }
                    }
                }
            }
        }

        ToggleRow {
            visible: GlobalConfig.general.logo !== "" && GlobalConfig.general.logo !== "caelestia"
            text: qsTr("Tint custom logo")
            subtext: qsTr("Apply the Material You accent color to your custom logo")
            checked: SysInfo.recolourCustomLogo
            onToggled: SysInfo.recolourCustomLogo = checked
        }

        StepperRow {
            visible: GlobalConfig.general.logo !== "" && GlobalConfig.general.logo !== "caelestia"
            label: qsTr("Logo size (%)")
            value: SysInfo.customLogoSize
            from: 50
            to: 200
            stepSize: 10
            onMoved: v => SysInfo.customLogoSize = v
        }

        ToggleRow {
            last: true
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal when the cursor reaches the screen edge")
            checked: Config.launcher.showOnHover
            onToggled: GlobalConfig.launcher.showOnHover = checked
        }

        SectionHeader {
            text: qsTr("Display")
        }

        ToggleRow {
            first: true
            text: qsTr("Browse apps when search is empty")
            subtext: qsTr("Show the categorized app grid in the launcher when the search field is empty")
            checked: Config.launcher.showBrowseOnEmpty
            onToggled: GlobalConfig.launcher.showBrowseOnEmpty = checked
        }

        ToggleRow {
            text: qsTr("Show power menu")
            subtext: qsTr("Show the quick session controls (shutdown, sleep, logout) at the bottom")
            checked: Config.launcher.showPowerMenu
            onToggled: GlobalConfig.launcher.showPowerMenu = checked
        }

        StepperRow {
            label: qsTr("Max items shown")
            value: Config.launcher.maxShown
            from: 1
            to: 20
            stepSize: 1
            onMoved: v => GlobalConfig.launcher.maxShown = v
        }

        StepperRow {
            label: qsTr("Max wallpapers")
            value: Config.launcher.maxWallpapers
            from: 1
            to: 30
            stepSize: 1
            onMoved: v => GlobalConfig.launcher.maxWallpapers = v
        }

        StepperRow {
            label: qsTr("Hover trigger depth")
            subtext: qsTr("Distance in from the screen edge that opens the launcher")
            value: Config.launcher.hoverThickness
            from: 1
            to: 100
            stepSize: 1
            onMoved: v => GlobalConfig.launcher.hoverThickness = v
        }

        StepperRow {
            label: qsTr("Hover trigger width")
            subtext: qsTr("How much of the bottom edge opens the launcher, as a percentage of its width")
            value: Config.launcher.hoverWidth
            from: 10
            to: 100
            stepSize: 5
            onMoved: v => GlobalConfig.launcher.hoverWidth = v
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the launcher opens")
            value: Config.launcher.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.launcher.dragThreshold = v
        }

        SectionHeader {
            text: qsTr("Clipboard")
        }

        StepperRow {
            first: true
            label: qsTr("Max clipboard entries")
            subtext: qsTr("Number of copied items kept in history")
            value: Config.launcher.clipboardMaxEntries
            from: 1
            to: 100
            stepSize: 1
            onMoved: v => GlobalConfig.launcher.clipboardMaxEntries = v
        }

        ToggleRow {
            last: true
            text: qsTr("Confirm clear")
            subtext: qsTr("Ask before clearing the clipboard history")
            checked: GlobalConfig.launcher.confirmClearClipboard
            onToggled: GlobalConfig.launcher.confirmClearClipboard = checked
        }

        SectionHeader {
            text: qsTr("Behavior")
        }

        ToggleRow {
            first: true
            text: qsTr("Vim keybinds")
            subtext: qsTr("Navigate results with Ctrl+hjkl")
            checked: GlobalConfig.launcher.vimKeybinds
            onToggled: GlobalConfig.launcher.vimKeybinds = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Enable dangerous actions")
            subtext: qsTr("Allow actions that shut down or log out")
            checked: GlobalConfig.launcher.enableDangerousActions
            onToggled: GlobalConfig.launcher.enableDangerousActions = checked
        }

        SectionHeader {
            text: qsTr("Fuzzy search")
        }

        ToggleRow {
            first: true
            text: qsTr("Apps")
            checked: GlobalConfig.launcher.useFuzzy.apps
            onToggled: GlobalConfig.launcher.useFuzzy.apps = checked
        }

        ToggleRow {
            text: qsTr("Actions")
            checked: GlobalConfig.launcher.useFuzzy.actions
            onToggled: GlobalConfig.launcher.useFuzzy.actions = checked
        }

        ToggleRow {
            text: qsTr("Schemes")
            checked: GlobalConfig.launcher.useFuzzy.schemes
            onToggled: GlobalConfig.launcher.useFuzzy.schemes = checked
        }

        ToggleRow {
            text: qsTr("Variants")
            checked: GlobalConfig.launcher.useFuzzy.variants
            onToggled: GlobalConfig.launcher.useFuzzy.variants = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Wallpapers")
            checked: GlobalConfig.launcher.useFuzzy.wallpapers
            onToggled: GlobalConfig.launcher.useFuzzy.wallpapers = checked
        }
    }
}
