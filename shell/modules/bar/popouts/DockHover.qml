import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Caelestia.Config
import qs.components
import qs.components.images
import qs.services
import qs.utils

StyledRect {
    id: root

    required property PopoutState popouts
    property var model: popouts.dockModel
    // Resolved through the same helper the taskbar tile uses, so the hover popup
    // can never disagree with the tile it belongs to.
    readonly property string iconSource: model ? WinIcons.sourceFor(model.entry, model.appClass, model.iconName, model.pid ?? 0) : ""
    property MprisPlayer player: {
        if (!model) return null;
        return Players.list.find(p => p.identity.toLowerCase().includes(model.appClass.toLowerCase()) || (model.id && p.identity.toLowerCase().includes(model.id.toLowerCase().replace(".desktop", "")))) || null;
    }
    // Injected by Content.qml's Popout.
    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false
    readonly property int previewWidth: Math.round(Tokens.sizes.bar.windowPreviewSize * scaleOffset)
    readonly property int cardWidth: (root.model && root.model.toplevels && root.model.toplevels.length > 1) ? Math.round(previewWidth * 0.55) : previewWidth
    // root.model is a snapshot taken when the popout opened, not a live binding, so
    // it never learns a window closed on its own — that card's screencast dies
    // (KWin has nothing left to stream) and falls back to the app icon instead of
    // the card disappearing. Closing a window here therefore also has to patch the
    // snapshot by hand: drop the closed toplevel, and if none are left, close the
    // popout outright unless the app is pinned, in which case the empty-state
    // fallback below is the correct thing to show.

    function closeToplevel(address: string): void {
        if (Kwin.windowList.length > 0) {
            Kwin.closeWindow(address);
        } else {
            Kwin.dispatch(Kwin.usingLua ? `hl.dsp.window.close({ window = "address:0x${address}" })` : `closewindow address:0x${address}`);
        }

        if (!root.model || !root.model.toplevels)
            return;

        const remaining = root.model.toplevels.filter(t => String(t.address) !== String(address));
        if (remaining.length === root.model.toplevels.length)
            return;

        if (remaining.length === 0 && !root.model.isPinned) {
            root.popouts.hasCurrent = false;
            return;
        }

        root.popouts.dockModel = Object.assign({}, root.model, { toplevels: remaining });
    }
    radius: Tokens.rounding.medium
    color: Colours.tPalette.m3surfaceContainer
    clip: true
    implicitWidth: mainLayout.implicitWidth + Tokens.padding.medium * scaleOffset * 2
    implicitHeight: mainLayout.implicitHeight + Tokens.padding.medium * scaleOffset * 2
    // Explicit sizing for popout positioning calculations
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        id: mainLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium * scaleOffset
        spacing: Tokens.spacing.small
        // Fallback for pinned apps with no active windows

        StyledRect {
            implicitWidth: fallbackLayout.implicitWidth + Tokens.padding.small * scaleOffset * 2
            implicitHeight: fallbackLayout.implicitHeight + Tokens.padding.small * scaleOffset * 2
            visible: !root.model || !root.model.toplevels || root.model.toplevels.length === 0
            radius: Tokens.rounding.small
            color: "transparent"

            StateLayer {
                anchors.margins: -Tokens.padding.medium * scaleOffset / 2
                anchors.leftMargin: -Tokens.padding.medium * scaleOffset
                anchors.rightMargin: -Tokens.padding.medium * scaleOffset
                radius: parent.radius
                onClicked: {
                    if (root.model && root.model.entry) {
                        const subCmd = root.model.entry.runInTerminal
                            ? [...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...root.model.entry.command]
                            : root.model.entry.command;
                        Quickshell.execDetached({
                            command: Launch.wrap(subCmd),
                            workingDirectory: root.model.entry.workingDirectory
                        });
                    }
                    root.popouts.hasCurrent = false;
                }
            }
            RowLayout {
                id: fallbackLayout

                anchors.centerIn: parent
                spacing: Tokens.spacing.medium

                IconImage {
                    asynchronous: true
                    implicitSize: fallbackText.implicitHeight
                    source: root.iconSource
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledText {
                    id: fallbackText

                    text: root.model ? (root.model.entry ? root.model.entry.name : root.model.appClass) : ""
                    font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                    elide: Text.ElideRight
                }
            }
        }
        // Active windows row - live thumbnail previews, native Plasma taskbar style
        RowLayout {
            id: windowsRow

            visible: root.model && root.model.toplevels && root.model.toplevels.length > 0
            spacing: Tokens.spacing.medium

            Repeater {
                model: root.model && root.model.toplevels ? root.model.toplevels : []
                delegate: StyledRect {
                    id: card

                    required property var modelData
                    required property int index
                    // Match thumbnail height to the window's actual aspect ratio
                    // (modelData.width/height come from KWin's frameGeometry via DBus),
                    // clamped to a reasonable max height so tall windows don't explode
                    // the popout.  Fall back to 16:10 if the geometry isn't available yet.
                    readonly property real windowAspect: {
                        const w = card.modelData.width;
                        const h = card.modelData.height;
                        return (w > 0 && h > 0) ? (w / h) : (16.0 / 10.0);
                    }
                    readonly property int thumbHeight: {
                        const raw = Math.round(root.cardWidth / windowAspect);
                        const max = Math.round(root.cardWidth * 1.6); // never taller than 1.6× width
                        const min = Math.round(root.cardWidth * 0.4);
                        return Math.max(min, Math.min(max, raw));
                    }

                    implicitWidth: root.cardWidth
                    implicitHeight: cardLayout.implicitHeight
                    radius: Tokens.rounding.small
                    color: "transparent"

                    HoverHandler {
                        id: cardHover
                    }
                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: {
                            if (card.modelData.address) {
                                if (Kwin.windowList.length > 0) {
                                    Kwin.focusWindow(card.modelData.address);
                                } else {
                                    Kwin.dispatch(Kwin.usingLua ? `hl.dsp.focus({ window = "address:0x${card.modelData.address}" })` : `focuswindow address:0x${card.modelData.address}`);
                                }
                            }
                            root.popouts.hasCurrent = false;
                        }
                    }
                    ColumnLayout {
                        id: cardLayout

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: Tokens.spacing.small / 2

                        StyledClippingRect {
                            id: thumb

                            color: Colours.tPalette.m3surfaceContainerHighest
                            radius: Tokens.rounding.small

                            WindowPreview {
                                anchors.fill: parent
                                address: card.modelData?.address ?? ""
                                fallbackIcon: root.iconSource
                                sourceAspect: card.windowAspect
                            }

                            // Close button - only revealed while hovering this thumbnail
                            StyledRect {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: Tokens.padding.small
                                implicitWidth: closeIcon.implicitHeight + Tokens.padding.small * scaleOffset * 2
                                implicitHeight: closeIcon.implicitHeight + Tokens.padding.small * scaleOffset * 2
                                radius: Tokens.rounding.small
                                color: Colours.tPalette.m3surfaceVariant
                                opacity: cardHover.hovered ? 1 : 0
                                visible: opacity > 0.01

                                Behavior on opacity {
                                    Anim {}
                                }
                                StateLayer {
                                    anchors.fill: parent
                                    radius: Tokens.rounding.small
                                    onClicked: {
                                        if (card.modelData.address)
                                            root.closeToplevel(card.modelData.address);
                                    }
                                }
                                MaterialIcon {
                                    id: closeIcon

                                    anchors.centerIn: parent
                                    text: "close"
                                    fontStyle.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                                }
                            }
                            Layout.preferredWidth: root.cardWidth
                            Layout.preferredHeight: card.thumbHeight
                        }
                        StyledText {
                            id: titleText

                            text: card.modelData.title || ""
                            font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            Layout.preferredWidth: root.cardWidth
                        }
                    }
                }
            }
            Layout.alignment: Qt.AlignLeft
        }
        // Media controls separator
        StyledRect {
            implicitHeight: 1
            color: Colours.tPalette.m3surfaceVariant
            visible: !!root.player
            Layout.fillWidth: true
        }
        // Media controls
        RowLayout {
            spacing: Tokens.spacing.medium
            visible: !!root.player

            Item {
                implicitWidth: prevIcon.implicitHeight + Tokens.padding.small * scaleOffset * 2
                implicitHeight: prevIcon.implicitHeight + Tokens.padding.small * scaleOffset * 2
                visible: root.player ? root.player.canGoPrevious : false

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.small
                    onClicked: root.player.previous()
                }
                MaterialIcon {
                    id: prevIcon

                    anchors.centerIn: parent
                    text: "skip_previous"
                    fontStyle.pointSize: Tokens.font.body.large.pointSize * root.fontScale
                }
            }
            Item {
                implicitWidth: playIcon.implicitHeight + Tokens.padding.small * scaleOffset * 2
                implicitHeight: playIcon.implicitHeight + Tokens.padding.small * scaleOffset * 2
                visible: root.player ? root.player.canTogglePlaying : false

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.small
                    onClicked: root.player.togglePlaying()
                }
                MaterialIcon {
                    id: playIcon

                    anchors.centerIn: parent
                    text: (root.player && root.player.isPlaying) ? "pause" : "play_arrow"
                    fontStyle.pointSize: Tokens.font.body.large.pointSize * root.fontScale
                }
            }
            Item {
                implicitWidth: nextIcon.implicitHeight + Tokens.padding.small * scaleOffset * 2
                implicitHeight: nextIcon.implicitHeight + Tokens.padding.small * scaleOffset * 2
                visible: root.player ? root.player.canGoNext : false

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.small
                    onClicked: root.player.next()
                }
                MaterialIcon {
                    id: nextIcon

                    anchors.centerIn: parent
                    text: "skip_next"
                    fontStyle.pointSize: Tokens.font.body.large.pointSize * root.fontScale
                }
            }
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
