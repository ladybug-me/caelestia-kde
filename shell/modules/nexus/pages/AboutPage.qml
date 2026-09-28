import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.nexus.common

PageBase {
    id: root


    property string pluginCount

    property string quickshellVersion
    property string cliVersion

    title: qsTr("About")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            running: true
            command: ["quickshell", "--version"]
            stdout: StdioCollector {
                onStreamFinished: root.quickshellVersion = text.trim().split(" ")[1] ?? ""
            }
        }

        Process {
            running: true
            command: ["sh", "-c", "caelestia --version 2>/dev/null"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const m = text.match(/^caelestia\s+(\S+)/);
                    root.cliVersion = m ? m[1] : "";
                }
            }
        }
        Process {
            running: true
            command: ["caelestia", "shell", "plugins", "count"]
            stdout: StdioCollector {
                onStreamFinished: root.pluginCount = text.trim()
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: hero.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: hero

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.small

                AnimatedLogo {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spacing.small
                    text: "Caelestia"
                    font: Tokens.font.headline.builders.large.width(110).build()
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: CUtils.version ? `v${CUtils.version}` : "…"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }
        }

        SectionHeader {
            text: qsTr("System")
        }

        InfoRow {
            first: true
            label: qsTr("Hostname")
            value: SysInfo.hostname
        }

        InfoRow {
            label: qsTr("Device")
            value: SysInfo.device
        }

        InfoRow {
            label: qsTr("Distro")
            value: SysInfo.osPrettyName || SysInfo.osName
        }

        InfoRow {
            label: qsTr("Kernel")
            value: SysInfo.kernel
        }

        InfoRow {
            last: true
            label: qsTr("Firmware")
            value: SysInfo.firmware
        }

        SectionHeader {
            text: qsTr("Software")
        }

        InfoRow {
            first: true
            label: qsTr("Shell")
            value: CUtils.version || "…"
        }

        InfoRow {
            label: qsTr("CLI")
            value: root.cliVersion || "…"
        }

        InfoRow {
            label: qsTr("Quickshell")
            value: root.quickshellVersion || "…"
        }

        InfoRow {
            last: true
            label: qsTr("Qt")
            value: CUtils.qtVersion || "…"
        }

        SectionHeader {
            text: qsTr("Plugins")
        }

        // Reports the count and links through to the plugin manager. A bare
        // number with nothing behind it is a dead end: the page that lists the
        // plugins is where anyone reading this number wants to go (#578).
        NavRow {
            first: true
            last: true
            icon: "extension"
            label: qsTr("Enabled plugins")
            status: root.pluginCount || "…"
            onClicked: {
                // Resolve by key rather than a literal index: PageDictionary is
                // positional and entries must not be reordered independently.
                const index = PageRegistry.indexForKey("plugins");
                if (index >= 0)
                    root.nState.currentPageIdx = index;
            }
        }

        SectionHeader {
            text: qsTr("Advanced")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Debug Mode")
            subtext: qsTr("Enable verbose debug logging for troubleshooting. Run 'caelestia shell -l' to view.")
            checked: GlobalConfig.general.debugLogs
            onClicked: GlobalConfig.general.debugLogs = !GlobalConfig.general.debugLogs
        }
    }
}
