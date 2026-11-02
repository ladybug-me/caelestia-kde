pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> modeItems: [
        MenuItem {
            text: qsTr("No proxy")
            value: "none"
        },
        MenuItem {
            text: qsTr("Manual")
            value: "manual"
        },
        MenuItem {
            text: qsTr("Automatic (PAC script)")
            value: "pac"
        },
        MenuItem {
            text: qsTr("Detect automatically")
            value: "auto"
        },
        MenuItem {
            text: qsTr("Use environment variables")
            value: "env"
        }
    ]

    /// The addresses the chosen mode reads, so the page and the mode cannot disagree
    /// about which fields exist.
    readonly property var fields: {
        if (root.mode === "manual")
            return [
                { label: qsTr("HTTP proxy"), key: "http", hint: "http://host:port" },
                { label: qsTr("HTTPS proxy"), key: "https", hint: "http://host:port" },
                { label: qsTr("FTP proxy"), key: "ftp", hint: "http://host:port" },
                { label: qsTr("SOCKS proxy"), key: "socks", hint: "socks://host:port" },
                { label: qsTr("No proxy for"), key: "noProxy", hint: qsTr("Comma separated hosts") }
            ];
        if (root.mode === "pac")
            return [{ label: qsTr("Script address"), key: "pac", hint: "http://host/proxy.pac" }];
        return [];
    }

    readonly property string mode: Proxy.mode
    readonly property bool manual: root.mode === "manual"

    function modeItem(): MenuItem {
        return root.modeItems.find(item => item.value === root.mode) ?? root.modeItems[0];
    }

    title: qsTr("Proxy")
    isSubPage: true

    Component.onCompleted: Proxy.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText {
            Layout.fillWidth: true
            visible: Proxy.lastError !== ""
            text: Proxy.lastError
            color: Colours.palette.m3error
            font: NexusStyle.secondaryFont
            wrapMode: Text.Wrap
        }

        SelectRow {
            label: qsTr("Mode")
            subtext: qsTr("How applications decide where to send requests")
            first: true
            last: root.fields.length === 0
            menuItems: root.modeItems
            active: root.modeItem()
            fallbackText: root.mode
            onSelected: item => Proxy.setMode(item.value)
        }

        Repeater {
            model: root.fields

            delegate: TextFieldRow {
                required property var modelData
                required property int index

                first: index === 0
                last: index === root.fields.length - 1
                label: modelData.label
                placeholderText: modelData.hint
                value: Proxy.settings[modelData.key] ?? ""
                onEditingFinished: value => Proxy.set(modelData.key, value)
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            text: qsTr("Stored in kioslaverc, which KDE applications read: Plasma, Dolphin, Konsole and the rest. Programs started from a shell keep whatever their environment says until they are restarted.")
            color: Colours.palette.m3onSurfaceVariant
            font: NexusStyle.secondaryFont
            wrapMode: Text.Wrap
        }
    }
}
