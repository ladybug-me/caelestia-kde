pragma ComponentBehavior: Bound

import qs.services.api
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property int bundledCount: {
        let n = 0;
        for (let i = 0; i < CaelestiaApi.plugins.available.count; i++) {
            if (CaelestiaApi.plugins.available.get(i).source === "bundled") n++;
        }
        return n;
    }
    readonly property int userCount: {
        let n = 0;
        for (let i = 0; i < CaelestiaApi.plugins.available.count; i++) {
            if (CaelestiaApi.plugins.available.get(i).source === "user") n++;
        }
        return n;
    }
    property int currentTab: 0 // 0 = Installed, 1 = Store
    property string storeBranch: "main"

    function resolveIconUrl(iconString, basePath, isStorePlugin) {
        if (!iconString || iconString === "default") return "";
        let s = iconString.toLowerCase();
        let isImg = s.endsWith(".png") || s.endsWith(".jpg") || s.endsWith(".jpeg") || s.endsWith(".gif") || s.endsWith(".svg");
        if (!isImg) return "";
        
        if (iconString.indexOf("http://") === 0 || iconString.indexOf("https://") === 0 || iconString.indexOf("file://") === 0) return iconString;
        if (iconString.indexOf("/") === 0) return "file://" + iconString;
        
        if (isStorePlugin) {
            return "https://raw.githubusercontent.com/ladybug-me/caelestia-kde-plugins/" + root.storeBranch + "/" + basePath + "/" + iconString;
        }
        return "file://" + basePath + "/" + iconString;
    }
    
    function resolveIconText(iconString) {
        if (!iconString || iconString === "default") return "extension";
        let s = iconString.toLowerCase();
        let isImg = s.endsWith(".png") || s.endsWith(".jpg") || s.endsWith(".jpeg") || s.endsWith(".gif") || s.endsWith(".svg");
        if (isImg) return "extension";
        return iconString;
    }

    title: qsTr("Plugins")

    headerActions: [
        TextButton {
            text: qsTr("Refresh")
            type: TextButton.Tonal
            visible: root.currentTab === 1
            onClicked: {
                PluginStore.fetchIndex(root.storeBranch);
            }
        },
        TextButton {
            text: qsTr("Restart Shell")
            type: TextButton.Filled
            visible: PluginStore.restartRequired
            onClicked: Launch.exec(["bash", "-c", `bash "${Quickshell.shellPath("scripts/restart_shell.sh")}"; sleep 1; caelestia shell nexus openPage 15 0`])
        }
    ]

    Component.onCompleted: {
        if (PluginStore.storePlugins.count === 0) {
            PluginStore.fetchIndex(root.storeBranch);
        }
    }

    Item {
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0
        PluginSettingsPopup {
            id: settingsPopup
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            ToggleButton {
                Layout.fillWidth: true
                explicitWidth: (root.cappedWidth - Tokens.spacing.medium) / 2
                label: qsTr("Installed")
                icon: "extension"
                toggled: root.currentTab === 0
                onClicked: root.currentTab = 0
            }

            ToggleButton {
                Layout.fillWidth: true
                explicitWidth: (root.cappedWidth - Tokens.spacing.medium) / 2
                label: qsTr("Store")
                icon: "store"
                toggled: root.currentTab === 1
                onClicked: root.currentTab = 1
            }
        }

        Item { Layout.preferredHeight: Tokens.spacing.large }

        ConnectedRect {
            visible: PluginStore.restartRequired
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: restartStatus.implicitHeight + Tokens.padding.largeIncreased * 2

            RowLayout {
                id: restartStatus

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignTop
                    text: "restart_alt"
                    fontStyle: Tokens.font.icon.large
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("A shell restart is required for changes to take effect")
                        font: Tokens.font.title.medium
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.currentTab === 0
            spacing: Tokens.spacing.extraSmall / 2

            SectionHeader {
                first: true
                text: qsTr("Shell Plugins")
                visible: root.bundledCount > 0
            }
            Repeater {
                id: bundledRepeater

                model: CaelestiaApi.plugins.available
                delegate: ExpandablePluginRow {
                    id: bundledDelegate

                    required property int index
                    required property string name
                    required property string version
                    required property string description
                    required property string source
                    required property string id
                    required property bool enabled
                    required property var settings
                    required property string path
                    required property string mediaurl
                    required property string authorName
                    required property string icon
                    required property bool restart

                    Layout.fillWidth: true
                    visible: bundledDelegate.source === "bundled"

                    titleText: bundledDelegate.name
                    versionText: bundledDelegate.version
                    descriptionText: bundledDelegate.description
                    authorNameText: bundledDelegate.authorName
                    iconText: root.resolveIconText(bundledDelegate.icon)
                    iconImageUrl: root.resolveIconUrl(bundledDelegate.icon, bundledDelegate.path, false)
                    mediaUrl: {
                        if (!mediaurl) return "";
                        if (mediaurl.indexOf("http://") === 0 || mediaurl.indexOf("https://") === 0 || mediaurl.indexOf("file://") === 0) return mediaurl;
                        if (mediaurl.indexOf("/") === 0) return "file://" + mediaurl;
                        return "file://" + path + "/" + mediaurl;
                    }

                    actionComponent: Component {
                        RowLayout {
                            spacing: Tokens.spacing.medium

                            StyledSwitch {
                                checked: bundledDelegate.enabled
                                onToggled: {
                                    PluginLoader.setPluginEnabled(bundledDelegate.id || bundledDelegate.name, !bundledDelegate.enabled);
                                }
                            }
                            
                            IconButton {
                                icon: "settings"
                                type: IconButton.Tonal
                                visible: bundledDelegate.settings && bundledDelegate.settings.count > 0
                                onClicked: {
                                    settingsPopup.pluginId = bundledDelegate.id || bundledDelegate.name;
                                    settingsPopup.pluginName = bundledDelegate.name;
                                    settingsPopup.settingsSchema = bundledDelegate.settings;
                                    settingsPopup.open();
                                }
                            }
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("User Installed")
                visible: root.userCount > 0
                first: root.bundledCount === 0
            }
            Repeater {
                id: userRepeater

                model: CaelestiaApi.plugins.available
                delegate: ExpandablePluginRow {
                    id: userDelegate

                    required property int index
                    required property string name
                    required property string version
                    required property string description
                    required property string source
                    required property string id
                    required property bool enabled
                    required property var settings
                    required property string path
                    required property string mediaurl
                    required property string authorName
                    required property string icon
                    required property bool restart

                    Layout.fillWidth: true
                    visible: userDelegate.source === "user"

                    titleText: userDelegate.name
                    versionText: userDelegate.version
                    descriptionText: userDelegate.description
                    authorNameText: userDelegate.authorName
                    iconText: root.resolveIconText(userDelegate.icon)
                    iconImageUrl: root.resolveIconUrl(userDelegate.icon, userDelegate.path, false)
                    mediaUrl: {
                        if (!mediaurl) return "";
                        if (mediaurl.indexOf("http://") === 0 || mediaurl.indexOf("https://") === 0 || mediaurl.indexOf("file://") === 0) return mediaurl;
                        if (mediaurl.indexOf("/") === 0) return "file://" + mediaurl;
                        return "file://" + path + "/" + mediaurl;
                    }

                    actionComponent: Component {
                        RowLayout {
                            spacing: Tokens.spacing.medium

                            StyledSwitch {
                                checked: userDelegate.enabled
                                onToggled: {
                                    PluginLoader.setPluginEnabled(userDelegate.id || userDelegate.name, !userDelegate.enabled);
                                }
                            }

                            IconButton {
                                icon: "settings"
                                type: IconButton.Tonal
                                visible: userDelegate.settings && userDelegate.settings.count > 0
                                onClicked: {
                                    settingsPopup.pluginId = userDelegate.id || userDelegate.name;
                                    settingsPopup.pluginName = userDelegate.name;
                                    settingsPopup.settingsSchema = userDelegate.settings;
                                    settingsPopup.open();
                                }
                            }

                            IconButton {
                                icon: "delete"
                                type: IconButton.Tonal
                                onClicked: {
                                    PluginStore.removePlugin(userDelegate.id || userDelegate.name);
                                }
                            }
                        }
                    }
                }
            }

            ConnectedRect {
                visible: CaelestiaApi.plugins.available.count === 0
                Layout.fillWidth: true
                first: true
                last: true
                implicitHeight: statusInst.implicitHeight + Tokens.padding.largeIncreased * 2

                RowLayout {
                    id: statusInst

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        Layout.alignment: Qt.AlignTop
                        text: "extension_off"
                        fontStyle: Tokens.font.icon.large
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("No plugins installed")
                            font: Tokens.font.title.medium
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.currentTab === 1
            spacing: Tokens.spacing.extraSmall / 2

            ConnectedRect {
                visible: PluginStore.loading || PluginStore.installing || PluginStore.error
                Layout.fillWidth: true
                first: true
                last: true
                implicitHeight: storeStatusInst.implicitHeight + Tokens.padding.largeIncreased * 2

                RowLayout {
                    id: storeStatusInst

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        Layout.alignment: Qt.AlignTop
                        text: PluginStore.error ? "error" : "downloading"
                        fontStyle: Tokens.font.icon.large
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: PluginStore.error ? PluginStore.errorMessage : (PluginStore.installing ? PluginStore.installProgress : qsTr("Loading store..."))
                            font: Tokens.font.title.medium
                        }
                    }
                }
            }

            SectionHeader {
                first: true
                text: qsTr("Available Plugins")
                visible: storeRepeater.count > 0 && !PluginStore.error
            }

            Repeater {
                id: storeRepeater

                model: PluginStore.storePlugins
                delegate: ExpandablePluginRow {
                    id: storeDelegate

                    required property int index
                    required property string pluginId
                    required property string name
                    required property string version
                    required property string description
                    required property string authorName
                    required property string icon
                    required property string type
                    required property bool restart
                    required property string path
                    required property string mediaurl

                    readonly property bool isInstalled: PluginStore.installedPluginIds.indexOf(storeDelegate.pluginId) !== -1
                    readonly property bool isUpdateAvailable: {
                        if (!isInstalled)
                            return false;
                        for (let i = 0; i < CaelestiaApi.plugins.available.count; i++) {
                            let p = CaelestiaApi.plugins.available.get(i);
                            if (p.id === storeDelegate.pluginId && p.version && storeDelegate.version) {
                                let v1 = storeDelegate.version.split('.');
                                let v2 = p.version.split('.');
                                for (let j = 0; j < Math.max(v1.length, v2.length); j++) {
                                    let n1 = parseInt(v1[j] || 0);
                                    let n2 = parseInt(v2[j] || 0);
                                    if (n1 > n2) return true;
                                    if (n1 < n2) break;
                                }
                            }
                        }
                        return false;
                    }

                    Layout.fillWidth: true

                    titleText: storeDelegate.name
                    versionText: storeDelegate.version
                    descriptionText: storeDelegate.description
                    authorNameText: storeDelegate.authorName
                    iconText: root.resolveIconText(storeDelegate.icon)
                    iconImageUrl: root.resolveIconUrl(storeDelegate.icon, storeDelegate.path, true)
                    mediaUrl: {
                        if (!storeDelegate.mediaurl) return "";
                        if (storeDelegate.mediaurl.indexOf("http://") === 0 || storeDelegate.mediaurl.indexOf("https://") === 0 || storeDelegate.mediaurl.indexOf("file://") === 0) return storeDelegate.mediaurl;
                        if (storeDelegate.mediaurl.indexOf("/") === 0) return "https://raw.githubusercontent.com/ladybug-me/caelestia-kde-plugins/" + root.storeBranch + storeDelegate.mediaurl;
                        return "https://raw.githubusercontent.com/ladybug-me/caelestia-kde-plugins/" + root.storeBranch + "/" + storeDelegate.path + "/" + storeDelegate.mediaurl;
                    }

                    actionComponent: Component {
                        TextButton {
                            text: storeDelegate.isUpdateAvailable ? qsTr("Update") : (storeDelegate.isInstalled ? qsTr("Installed") : qsTr("Install"))
                            enabled: (!storeDelegate.isInstalled || storeDelegate.isUpdateAvailable) && !PluginStore.installing
                            onClicked: {
                                PluginStore.installPlugin(storeDelegate.pluginId, storeDelegate.path, root.storeBranch, storeDelegate.restart);
                            }
                        }
                    }
                }
            }
        }
    }
}
