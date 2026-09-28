pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Blobs
import qs.components
import qs.components.controls
import qs.components.misc
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.nexus.common

FloatingWindow {
    id: root

    readonly property var entries: entriesModel.list
    readonly property var history: entriesModel.list.slice().sort((a, b) => b.revision - a.revision)
    readonly property int unreadCount: entriesModel.list.filter(entry => !root.acknowledged.includes(entry.revision)).length

    property var acknowledged: []
    property bool stateResolved: false
    property bool resolved: false
    property bool loaded: false
    property bool shown: false
    property bool hasAnimated: false

    function isUnread(entry: var): bool {
        return !root.acknowledged.includes(entry.revision);
    }

    function isVideo(url: var): bool {
        if (!url) return false;
        const lower = String(url).toLowerCase();
        return lower.endsWith(".mp4") || lower.endsWith(".webm") || lower.endsWith(".mkv") || lower.endsWith(".avi") || lower.endsWith(".mov");
    }

    function acknowledge(revisions: var): void {
        const next = root.acknowledged.slice();
        for (const revision of revisions)
            if (!next.includes(revision))
                next.push(revision);
        if (next.length === root.acknowledged.length)
            return;
        root.acknowledged = next;
        root.saveState();
    }

    function acknowledgeAll(): void {
        root.acknowledge(root.entries.map(entry => entry.revision));
    }

    function openEntry(entry: var): void {
        root.acknowledge([entry.revision]);
        stackView.push(featurePage, { "featureData": entry });
    }

    function saveState(): void {
        stateFile.setText(JSON.stringify({
            "schemaVersion": 1,
            "acknowledged": root.acknowledged
        }));
    }

    function resolveState(): void {
        if (root.resolved || !root.stateResolved)
            return;
        root.resolved = true;

        root.loaded = true;
        if (root.unreadCount > 0)
            root.reveal(true);
        else
            root.applyVisibility();
    }

    function reveal(animate: bool): void {
        if (!animate)
            root.hasAnimated = true;
        root.shown = true;
        root.applyVisibility();
    }

    function dismiss(): void {
        root.shown = false;
        root.applyVisibility();
    }

    function toggle(): void {
        if (root.visible)
            root.dismiss();
        else
            root.reveal(false);
    }

    function applyVisibility(): void {
        root.visible = root.loaded && root.shown;
    }

    color: Colours.tPalette.m3surface
    surfaceFormat.opaque: false
    title: qsTr("What's New in Caelestia")

    implicitWidth: 680
    implicitHeight: 480
    minimumSize.width: 680
    minimumSize.height: 480

    onVisibleChanged: {
        if (!root.visible && root.shown)
            root.shown = false;
    }

    BackgroundEffect.blurRegion: Region {
        Region { x: -10; y: -10; width: 1; height: 1 }
        Region { item: (GlobalConfig.appearance.transparency.enabled && GlobalConfig.appearance.blur) ? container : null }
    }

    Entries {
        id: entriesModel
    }

    FileView {
        id: stateFile

        printErrors: false
        path: `${Paths.state}/whatsnew.json`

        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.acknowledged = Array.isArray(data.acknowledged) ? data.acknowledged : [];
            } catch (e) {
                console.warn("WhatsNewWindow: ignoring unreadable state: " + e);
                root.acknowledged = [];
            }
            root.stateResolved = true;
            root.resolveState();
        }

        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                console.warn("WhatsNewWindow: could not read state: " + err);
            root.stateResolved = true;
            root.resolveState();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "whatsnew"
        description: qsTr("What's New")
        onPressed: root.toggle()
    }

    IpcHandler {
        function open(): void {
            root.reveal(false);
        }

        function toggle(): void {
            root.toggle();
        }

        target: "whatsnew"
    }

    Item {
        id: container

        anchors.fill: parent

        BlobGroup {
            id: blobGroup

            smoothing: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainerLow
        }

        BlobInvertedRect {
            anchors.fill: parent
            group: blobGroup
            opacity: Colours.tPalette.m3surfaceContainerLow.a
            radius: Tokens.rounding.large
            borderLeft: Tokens.padding.medium
            borderRight: Tokens.padding.medium
            borderTop: Tokens.padding.medium
            borderBottom: Tokens.padding.medium
        }

        StackView {
            id: stackView

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            initialItem: homePage

            clip: true
        }

        Component {
            id: homePage

            Item {
                id: homeRoot

                readonly property real startupBlockHeight: 90.38 + Tokens.spacing.large + titleText.implicitHeight
                readonly property real startupBlockY: (homeRoot.height - startupBlockHeight) / 2 - 40

                function openCurrent(): void {
                    const entry = root.history[featuresList.currentIndex];
                    if (entry)
                        root.openEntry(entry);
                }

                state: root.hasAnimated ? "loaded" : "startup"

                Keys.onEscapePressed: root.dismiss()

                Timer {
                    id: startupTimer

                    interval: 2300
                    running: root.shown && !root.hasAnimated

                    onTriggered: root.hasAnimated = true
                }

                Item {
                    id: logoItem

                    width: 128
                    height: 90.38
                    transformOrigin: Item.TopLeft
                    x: homeRoot.state === "startup" ? (homeRoot.width - width) / 2 : (homeRoot.width - (64 + Tokens.spacing.medium + titleText.implicitWidth)) / 2
                    y: homeRoot.state === "startup" ? homeRoot.startupBlockY : (46 - 45.19) / 2
                    scale: homeRoot.state === "startup" ? 1.0 : 64 / 128

                    AnimatedLogo {
                        id: logoAnim

                        anchors.fill: parent
                    }
                }

                StyledText {
                    id: titleText

                    text: qsTr("What's New in Caelestia")
                    font: Tokens.font.title.builders.large.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurface
                    x: homeRoot.state === "startup" ? (homeRoot.width - implicitWidth) / 2 : logoItem.x + 64 + Tokens.spacing.medium
                    y: homeRoot.state === "startup" ? homeRoot.startupBlockY + 90.38 + Tokens.spacing.large : (46 - implicitHeight) / 2
                }

                StyledText {
                    id: startupVersionText

                    text: CUtils.version ? "v" + CUtils.version : ""
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurfaceVariant
                    x: homeRoot.state === "startup" ? (homeRoot.width - implicitWidth) / 2 : titleText.x
                    y: titleText.y + titleText.implicitHeight

                    opacity: homeRoot.state === "startup" ? 1 : 0
                }

                ListView {
                    id: featuresList

                    anchors.top: parent.top
                    anchors.topMargin: 46 + Tokens.spacing.large
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    opacity: homeRoot.state === "startup" ? 0 : 1
                    clip: true
                    spacing: Tokens.spacing.medium
                    model: root.history
                    keyNavigationEnabled: true
                    currentIndex: -1
                    focus: stackView.depth === 1

                    onCurrentIndexChanged: {
                        if (featuresList.currentIndex >= 0)
                            featuresList.positionViewAtIndex(featuresList.currentIndex, ListView.Contain);
                    }

                    Keys.onReturnPressed: homeRoot.openCurrent()
                    Keys.onEnterPressed: homeRoot.openCurrent()

                    footer: Item {
                        width: featuresList.width
                        height: 64 + Tokens.spacing.large

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.max(0, featuresList.height - featuresList.contentHeight) + (parent.height - implicitHeight) / 2
                            text: CUtils.version ? "v" + CUtils.version : ""
                            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    delegate: StyledRect {
                        id: delegateRect

                        required property var modelData

                        property var feature: modelData
                        property bool hasMedia: feature && !!feature.mediaUrl

                        width: ListView.view.width
                        height: contentColumn.implicitHeight + Tokens.padding.large * 2
                        radius: Tokens.rounding.extraLarge
                        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                        border.width: (featuresList.activeFocus && ListView.isCurrentItem) ? 2 : 0
                        border.color: Colours.palette.m3primary

                        Behavior on color { CAnim {} }

                        StateLayer {
                            anchors.fill: parent
                            topLeftRadius: parent.radius
                            topRightRadius: parent.radius
                            bottomLeftRadius: parent.radius
                            bottomRightRadius: parent.radius

                            onClicked: root.openEntry(feature)
                        }

                        ColumnLayout {
                            id: contentColumn

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.large

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.medium

                                StyledRect {
                                    Layout.preferredHeight: 48
                                    Layout.preferredWidth: 48
                                    radius: Tokens.rounding.full
                                    color: Colours.palette.m3secondaryContainer

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: (feature && feature.icon) ? feature.icon : (feature && root.isVideo(feature.mediaUrl) ? "videocam" : "new_releases")
                                        color: Colours.palette.m3onSecondaryContainer
                                        fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                                        grade: 25
                                        fill: 1
                                    }

                                    StyledRect {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        width: 12
                                        height: 12
                                        radius: Tokens.rounding.full
                                        color: Colours.palette.m3primary
                                        visible: root.isUnread(feature)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: feature ? feature.title : ""
                                        font: Tokens.font.body.large
                                        color: Colours.palette.m3onSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: feature ? feature.description : ""
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurfaceVariant
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
                                        maximumLineCount: 1
                                    }
                                }

                                MaterialIcon {
                                    text: "chevron_right"
                                    color: Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                                }
                            }
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.SlowEffects
                        }
                    }
                }

                Item {
                    id: fabContainer

                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Tokens.spacing.large
                    width: 56
                    height: 56
                    opacity: homeRoot.state === "startup" ? 0 : 1
                    visible: root.unreadCount > 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.SlowEffects
                        }
                    }

                    IconButton {
                        id: markAllBtn

                        anchors.fill: parent
                        type: IconButton.Filled
                        icon: "done_all"
                        isRound: true
                        activeFocusOnTab: true
                        font: Tokens.font.icon.builders.large.weight(Font.Medium).build()

                        onClicked: root.acknowledgeAll()

                        Keys.onReturnPressed: root.acknowledgeAll()
                        Keys.onSpacePressed: root.acknowledgeAll()
                    }
                }
            }
        }

        Component {
            id: featurePage

            Item {
                property var featureData
                property bool hasMedia: featureData && !!featureData.mediaUrl

                focus: stackView.depth === 2

                Keys.onEscapePressed: stackView.pop()

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Tokens.spacing.large

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        IconButton {
                            icon: "arrow_back"
                            type: IconButton.Tonal
                            onClicked: stackView.pop()
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: featureData ? featureData.title : ""
                            font: Tokens.font.title.builders.large.weight(Font.Medium).build()
                            color: Colours.palette.m3onSurface
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Item {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                        }
                    }

                    ScrollView {
                        id: expandedScrollView

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        clip: true

                        ColumnLayout {
                            width: expandedScrollView.availableWidth
                            spacing: Tokens.spacing.large

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 280
                                visible: hasMedia

                                StyledRect {
                                    anchors.fill: parent
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3surface
                                    opacity: 0.5
                                    visible: {
                                        if (!featureData) return false;
                                        if (featureData.mediaTransparent) return false;
                                        if (featureData.mediaUrl) {
                                            const url = featureData.mediaUrl.toLowerCase();
                                            if (url.endsWith(".png") || url.endsWith(".svg") || url.endsWith(".gif"))
                                                return false;
                                        }
                                        return true;
                                    }
                                }

                                AnimatedImage {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.small
                                    source: hasMedia ? entriesModel.mediaSource(featureData) : ""
                                    visible: hasMedia && !root.isVideo(featureData.mediaUrl)
                                    fillMode: Image.PreserveAspectFit
                                    playing: visible
                                }

                                VideoOutput {
                                    id: vidOut

                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.small
                                    visible: hasMedia && root.isVideo(featureData.mediaUrl)
                                    fillMode: VideoOutput.PreserveAspectFit
                                }

                                AudioOutput {
                                    id: aOut

                                    muted: true
                                }

                                MediaPlayer {
                                    videoOutput: vidOut
                                    audioOutput: aOut
                                    source: hasMedia ? entriesModel.mediaSource(featureData) : ""
                                    loops: MediaPlayer.Infinite

                                    Component.onCompleted: {
                                        if (hasMedia && root.isVideo(featureData.mediaUrl))
                                            play();
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: featureData ? featureData.description : ""
                                font: Tokens.font.body.large
                                color: Colours.palette.m3onSurfaceVariant
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }

                            IconTextButton {
                                Layout.alignment: Qt.AlignHCenter
                                visible: featureData && featureData.settingsPage !== undefined
                                icon: "settings"
                                text: qsTr("Open in Settings")
                                onClicked: {
                                    const pageIdx = PageRegistry.indexForKey(featureData.settingsPage);
                                    if (pageIdx >= 0) {
                                        WindowFactory.create(null, {
                                            initialPageIdx: pageIdx,
                                            initialSubPageIdx: featureData.settingsSubPage ?? -1
                                        });
                                        root.dismiss();
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
