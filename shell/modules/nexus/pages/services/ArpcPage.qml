import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Discord Rich Presence")
    isSubPage: true

    function saveToken(token) {
        if (!token) {
            Quickshell.execDetached(["secret-tool", "clear", "service", "caelestia-shell", "account", "steamgriddb"]);
        } else {
            Quickshell.execDetached(["bash", "-c", "secret-tool store --label=\"Caelestia SteamGridDB Key\" service caelestia-shell account steamgriddb <<< \"$1\"", "--", token]);
        }
    }

    property Process readTokenProc: Process {
        id: readTokenProc

        command: ["secret-tool", "lookup", "service", "caelestia-shell", "account", "steamgriddb"]
        stdout: StdioCollector {
            onStreamFinished: {
                tokenInput.text = text.trim();
            }
        }
    }

    Component.onCompleted: readTokenProc.running = true

    ColumnLayout {
        id: layout

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.medium

        SectionHeader {
            first: true
            text: qsTr("Broadcast settings")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Enable rich presence")
            subtext: qsTr("Broadcast custom presence to Vesktop")
            checked: GlobalConfig.services.arpcEnabled
            onToggled: GlobalConfig.services.arpcEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            text: qsTr("Auto-detect Steam games")
            subtext: qsTr("Automatically broadcast running Steam games")
            checked: GlobalConfig.services.arpcSteamAutoDetect
            onToggled: GlobalConfig.services.arpcSteamAutoDetect = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            text: qsTr("Broadcast Caelestia info")
            subtext: qsTr("Broadcast shell uptime and system info")
            checked: GlobalConfig.services.arpcCaelestiaInfo
            onToggled: GlobalConfig.services.arpcCaelestiaInfo = checked
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true
            last: true
            label: qsTr("Clear when idle")
            subtext: GlobalConfig.services.arpcIdleTimeout > 0 ? qsTr("Hide the presence after %1 minutes away").arg(Math.round(GlobalConfig.services.arpcIdleTimeout / 60)) : qsTr("Never hide the presence (minutes)")
            value: Math.round(GlobalConfig.services.arpcIdleTimeout / 60)
            from: 0
            to: 60
            stepSize: 1
            onMoved: v => GlobalConfig.services.arpcIdleTimeout = Math.round(v * 60)
        }

        SectionHeader {
            text: qsTr("SteamGridDB integration")
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: contentRow.implicitHeight + Tokens.padding.medium * 2

            ConnectedRect {
                id: bg

                anchors.fill: parent
                first: true
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
                        text: qsTr("SteamGridDB API Key")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: qsTr("Used to fetch game icons for Steam games")
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
                        placeholderText: qsTr("API Key...")
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

        SectionHeader {
            text: qsTr("Target windows picker")
        }

        AutoEnableRow {
            Layout.fillWidth: true
            first: true
            last: true
            icon: "touch_app"
            label: qsTr("Pick from running windows")
            status: qsTr("Select an open window to add to ARPC")
            onSelected: windowClass => {
                let list = Array.from(GlobalConfig.services.arpcTargetWindows);
                let labels = Array.from(GlobalConfig.services.arpcTargetWindowLabels);
                if (!list.includes(windowClass)) {
                    while (labels.length < list.length) labels.push("");
                    list.push(windowClass);
                    labels.push("");
                    GlobalConfig.services.arpcTargetWindows = list;
                    GlobalConfig.services.arpcTargetWindowLabels = labels;
                    GlobalConfig.save();
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(100, Math.min(300, targetList.contentHeight + Tokens.padding.medium * 2))
            color: Colours.layer(Colours.palette.m3surfaceContainer, 1)
            radius: Tokens.rounding.large

            ListView {
                id: targetList

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                orientation: ListView.Vertical
                spacing: Tokens.spacing.small
                model: GlobalConfig.services.arpcTargetWindows
                clip: true

                move: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }
                moveDisplaced: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }

                delegate: StyledRect {
                    id: delegateRect

                    required property string modelData
                    required property int index

                    width: ListView.view.width
                    height: 68
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                    radius: Tokens.rounding.medium

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        anchors.topMargin: Tokens.padding.small
                        anchors.bottomMargin: Tokens.padding.small
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.medium

                            IconImage {
                                Layout.alignment: Qt.AlignVCenter
                                implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.5)
                                source: Quickshell.iconPath(delegateRect.modelData, "image-missing")
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: delegateRect.modelData
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }

                            Item {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 28
                                implicitHeight: 28

                                StateLayer {
                                    anchors.fill: parent
                                    radius: 14
                                    onClicked: {
                                        let list = Array.from(GlobalConfig.services.arpcTargetWindows);
                                        let labels = Array.from(GlobalConfig.services.arpcTargetWindowLabels);
                                        list.splice(delegateRect.index, 1);
                                        if (delegateRect.index < labels.length) {
                                            labels.splice(delegateRect.index, 1);
                                        }
                                        GlobalConfig.services.arpcTargetWindows = list;
                                        GlobalConfig.services.arpcTargetWindowLabels = labels;
                                        GlobalConfig.save();
                                    }
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "close"
                                    font: Tokens.font.icon.small
                                }
                            }
                        }

                        StyledTextField {
                            id: labelInput
                            Layout.fillWidth: true
                            Layout.leftMargin: Math.round(Tokens.font.icon.large.pointSize * 1.5) + Tokens.spacing.medium
                            Layout.preferredHeight: 24

                            placeholderText: qsTr("Custom label (optional) - use {class}, {title}")
                            font: Tokens.font.label.small
                            verticalAlignment: TextInput.AlignVCenter

                            property bool initializing: true

                            function commitLabel() {
                                if (initializing) return;
                                let labels = Array.from(GlobalConfig.services.arpcTargetWindowLabels);
                                while (labels.length <= delegateRect.index) labels.push("");
                                labels[delegateRect.index] = text;
                                GlobalConfig.services.arpcTargetWindowLabels = labels;
                            }

                            onAccepted: {
                                commitLabel();
                                GlobalConfig.save();
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && !initializing) {
                                    commitLabel();
                                    GlobalConfig.save();
                                }
                            }

                            Component.onCompleted: {
                                let labels = GlobalConfig.services.arpcTargetWindowLabels;
                                if (delegateRect.index < labels.length && labels[delegateRect.index]) {
                                    text = labels[delegateRect.index];
                                }
                                initializing = false;
                            }
                        }
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Hidden Steam Games")
        }

        AutoEnableRow {
            Layout.fillWidth: true
            first: true
            last: true
            icon: "visibility_off"
            label: qsTr("Hide a running Steam game")
            status: qsTr("Select an open Steam game to prevent it from broadcasting")
            onSelected: windowClass => {
                let appId = windowClass.replace("steam_app_", "");
                let list = Array.from(GlobalConfig.services.arpcSteamBlacklist);
                if (!list.includes(appId)) {
                    list.push(appId);
                    GlobalConfig.services.arpcSteamBlacklist = list;
                    GlobalConfig.save();
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(100, Math.min(300, blacklistList.contentHeight + Tokens.padding.medium * 2))
            color: Colours.layer(Colours.palette.m3surfaceContainer, 1)
            radius: Tokens.rounding.large

            ListView {
                id: blacklistList

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                orientation: ListView.Vertical
                spacing: Tokens.spacing.small
                model: GlobalConfig.services.arpcSteamBlacklist
                clip: true

                move: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }
                moveDisplaced: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }

                delegate: StyledRect {
                    id: blacklistDelegateRect

                    required property string modelData
                    required property int index

                    width: ListView.view.width
                    height: 40
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                    radius: Tokens.rounding.medium

                    RowLayout {
                        id: blacklistItemLayout

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            Layout.alignment: Qt.AlignVCenter
                            text: "block"
                            font: Tokens.font.icon.medium
                            color: Colours.palette.m3error
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: "Steam App ID: " + blacklistDelegateRect.modelData
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 28
                            implicitHeight: 28

                            StateLayer {
                                anchors.fill: parent
                                radius: 14
                                onClicked: {
                                    let list = Array.from(GlobalConfig.services.arpcSteamBlacklist);
                                    list.splice(blacklistDelegateRect.index, 1);
                                    GlobalConfig.services.arpcSteamBlacklist = list;
                                    GlobalConfig.save();
                                }
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "close"
                                font: Tokens.font.icon.small
                            }
                        }
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Manual custom presence")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Enable manual override")
            subtext: qsTr("Force broadcast this custom presence and ignore all other apps")
            checked: GlobalConfig.services.arpcManualOverride
            onToggled: GlobalConfig.services.arpcManualOverride = checked
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: manualContent.implicitHeight + (Tokens.padding.medium * 2)
            color: Colours.layer(Colours.palette.m3surfaceContainer, 1)
            radius: Tokens.rounding.large

            ColumnLayout {
                id: manualContent

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                ColumnLayout {
                    spacing: Tokens.spacing.extraSmall
                    Layout.fillWidth: true

                    StyledText { text: "App/game name"; color: Colours.palette.m3onSurface }
                    StyledInputField {
                        id: manualAppName
                        Layout.fillWidth: true

                        text: GlobalConfig.services.arpcAppName
                        horizontalAlignment: TextInput.AlignLeft
                    }
                }

                ColumnLayout {
                    spacing: Tokens.spacing.extraSmall
                    Layout.fillWidth: true

                    StyledText { text: "Details"; color: Colours.palette.m3onSurface }
                    StyledInputField {
                        id: manualDetails
                        Layout.fillWidth: true

                        text: GlobalConfig.services.arpcDetails
                        horizontalAlignment: TextInput.AlignLeft
                    }
                }

                ColumnLayout {
                    spacing: Tokens.spacing.extraSmall
                    Layout.fillWidth: true

                    StyledText { text: "State"; color: Colours.palette.m3onSurface }
                    StyledInputField {
                        id: manualState
                        Layout.fillWidth: true

                        text: GlobalConfig.services.arpcState
                        horizontalAlignment: TextInput.AlignLeft
                    }
                }

                ColumnLayout {
                    spacing: Tokens.spacing.extraSmall
                    Layout.fillWidth: true

                    StyledText { text: "Large image key/URL"; color: Colours.palette.m3onSurface }
                    StyledInputField {
                        id: manualLargeImage
                        Layout.fillWidth: true

                        text: GlobalConfig.services.arpcLargeImage
                        horizontalAlignment: TextInput.AlignLeft
                    }
                }

                ColumnLayout {
                    spacing: Tokens.spacing.extraSmall
                    Layout.fillWidth: true

                    StyledText { text: "Small image key/URL"; color: Colours.palette.m3onSurface }
                    StyledInputField {
                        id: manualSmallImage
                        Layout.fillWidth: true

                        text: GlobalConfig.services.arpcSmallImage
                        horizontalAlignment: TextInput.AlignLeft
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    
                    IconTextButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Save presence")
                        icon: "save"
                        type: TextButton.Filled
                        onClicked: {
                            GlobalConfig.services.arpcAppName = manualAppName.text;
                            GlobalConfig.services.arpcDetails = manualDetails.text;
                            GlobalConfig.services.arpcState = manualState.text;
                            GlobalConfig.services.arpcLargeImage = manualLargeImage.text;
                            GlobalConfig.services.arpcSmallImage = manualSmallImage.text;
                            GlobalConfig.save();
                        }
                    }
                }
            }
        }
    }

    component AutoEnableRow: PopupRow {
        id: row

        readonly property int popupHeight: layout.height - y - Tokens.padding.large - Tokens.padding.extraExtraLarge

        signal selected(windowClass: string)

        keepPopupAsChild: {
            if (root.nState.animatingContainer || root.opacity < 1)
                return true;

            let p = root.parent;
            while (p && p.objectName !== "PageContainer")
                p = p.parent;
            return p?.opacity < 1;
        }
        popup.topMovement: Math.max(Tokens.sizes.nexus.minPopupHeight - popupHeight, Tokens.padding.large)

        Loader {
            anchors.centerIn: parent
            active: row.popup.animDriver > 0

            sourceComponent: Item {
                implicitWidth: Tokens.sizes.nexus.popupWidth
                implicitHeight: {
                    let maxH = CUtils.clamp(row.popupHeight, Tokens.sizes.nexus.minPopupHeight, Tokens.sizes.nexus.maxPopupHeight);
                    let contentH = list.contentHeight;
                    if (contentH > 0) return Math.min(contentH, maxH);
                    return maxH;
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    VerticalFadeListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Connections {
                            target: Kwin

                            function onWindowListChanged() {
                                list.updateModel();
                            }
                        }

                        function updateModel() {
                            let toplevels = [];
                            for (const toplevel of Kwin.windowList) {
                                if (toplevel.title || toplevel.class) {
                                    toplevels.push(toplevel);
                                }
                            }
                            list.model = toplevels.sort((a, b) => (a.title ?? "").localeCompare(b.title ?? ""));
                        }

                        Component.onCompleted: updateModel()

                        delegate: StateLayer {
                            id: windowItem

                            required property var modelData
                            required property int index

                            anchors.fill: undefined
                            anchors.left: list.contentItem.left
                            anchors.right: list.contentItem.right
                            implicitHeight: itemLayout.implicitHeight + itemLayout.anchors.margins * 2
                            radius: Tokens.rounding.small

                            onClicked: {
                                row.popup.open = false;
                                row.selected(modelData.class ?? "");
                            }

                            RowLayout {
                                id: itemLayout

                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.medium

                                IconImage {
                                    asynchronous: true
                                    implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                                    source: Quickshell.iconPath(windowItem.modelData.class ?? "", "image-missing")
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: windowItem.modelData.title ?? "Unknown"
                                        font: Tokens.font.body.small
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: windowItem.modelData.class ?? ""
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.label.small
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
