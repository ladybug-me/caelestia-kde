pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar.components as BarComponents
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("GitHub")
    isSubPage: true

    readonly property bool githubProblem: BarComponents.GithubStore.tokenMissing || BarComponents.GithubStore.lastError !== ""

    readonly property string githubStatusLabel: {
        if (BarComponents.GithubStore.tokenMissing)
            return qsTr("No token set");
        if (BarComponents.GithubStore.lastError !== "")
            return qsTr("Last fetch failed");
        if (BarComponents.GithubStore.available) {
            return BarComponents.GithubStore.username !== ""
                ? qsTr("Connected as %1").arg(BarComponents.GithubStore.username)
                : qsTr("Connected");
        }
        return qsTr("Not fetched yet");
    }

    readonly property string githubStatusDetail: {
        if (BarComponents.GithubStore.tokenMissing)
            return qsTr("Paste a token below and save it to enable the widget");
        if (BarComponents.GithubStore.lastError !== "")
            return BarComponents.GithubStore.lastError;
        return "";
    }

    readonly property string githubStatusIcon: githubProblem ? "error" : (BarComponents.GithubStore.available ? "check_circle" : "hourglass_empty")

    readonly property color githubStatusColour: githubProblem ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant

    function saveToken(token: string): void {
        saveProc.environment = ({ CAELESTIA_GITHUB_TOKEN: token });
        if (!token) {
            saveProc.command = ["secret-tool", "clear", "service", "caelestia-shell", "account", "github"];
        } else {
            saveProc.command = ["bash", "-c", "printf %s \"$CAELESTIA_GITHUB_TOKEN\" | secret-tool store --label=\"Caelestia GitHub Token\" service caelestia-shell account github"];
        }
        saveProc.running = true;
    }

    property Process saveProc: Process {
        id: saveProc

        onExited: code => {
            if (code === 0)
                BarComponents.GithubStore.refresh();
        }
    }

    property Process readTokenProc: Process {
        id: readTokenProc

        command: ["secret-tool", "lookup", "service", "caelestia-shell", "account", "github"]
        stdout: StdioCollector {
            onStreamFinished: {
                tokenInput.text = text.trim();
            }
        }
    }

    Component.onCompleted: readTokenProc.running = true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Configuration")
        }

        InfoRow {
            first: true
            icon: root.githubStatusIcon
            iconColour: root.githubStatusColour
            label: root.githubStatusLabel
            subtext: root.githubStatusDetail
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Component background")
            subtext: qsTr("Render a solid background behind the GitHub activity widget")
            checked: Config.bar.github.background
            onToggled: GlobalConfig.bar.github.background = checked
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: contentRow.implicitHeight + Tokens.padding.medium * 2

            ConnectedRect {
                id: bg

                anchors.fill: parent
                last: true
            }

            RowLayout {
                id: contentRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                Column {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: qsTr("Personal Access Token")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: qsTr("Used to fetch your contribution graph (read:user)")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                StyledRect {
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 32
                    radius: Tokens.rounding.small
                    color: Colours.layer(Colours.palette.m3surfaceVariant, 2)

                    StyledTextField {
                        id: tokenInput

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: "ghp_..."
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        onAccepted: root.saveToken(text)
                    }
                }

                IconButton {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    icon: "save"
                    onClicked: root.saveToken(tokenInput.text)
                }

                IconButton {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    icon: "close"
                    onClicked: {
                        tokenInput.text = ""
                        root.saveToken("")
                    }
                }
            }
        }
    }
}
