pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services

StyledRect {
    id: root

    required property string titleText
    required property string versionText
    required property string descriptionText
    property string authorNameText: ""
    property string iconText: "extension"
    property string iconImageUrl: ""

    default property Component actionComponent

    property bool isExpanded: false
    property string mediaUrl: ""



    function isVideo(url) {
        if (!url) return false;
        let lower = url.toString().toLowerCase();
        return lower.endsWith(".mp4") || lower.endsWith(".webm") || lower.endsWith(".mkv");
    }

    function isTransparentMedia(url) {
        if (!url) return false;
        let lower = url.toString().toLowerCase();
        return lower.endsWith(".png") || lower.endsWith(".svg") || lower.endsWith(".gif") || lower.endsWith(".webp");
    }

    implicitHeight: contentColumn.implicitHeight + Tokens.padding.large * 2
    
    radius: Tokens.rounding.large
    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, root.isExpanded ? 3 : 1)

    onIsExpandedChanged: {
        if (isExpanded && isVideo(mediaUrl)) {
            mediaPlay.play()
        } else if (!isExpanded && isVideo(mediaUrl)) {
            mediaPlay.pause()
        }
    }

    Behavior on color { CAnim {} }

    StateLayer {
        id: stateLayer

        anchors.fill: parent
        topLeftRadius: parent.radius
        topRightRadius: parent.radius
        bottomLeftRadius: parent.radius
        bottomRightRadius: parent.radius

        onClicked: root.isExpanded = !root.isExpanded
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

            StyledClippingRect {
                Layout.preferredHeight: 48
                Layout.preferredWidth: 48
                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer
                
                AnimatedImage {
                    id: pluginIconImage

                    anchors.fill: parent
                    source: root.iconImageUrl
                    visible: root.iconImageUrl !== ""
                    fillMode: Image.PreserveAspectCrop
                    playing: true
                    
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity { Anim { type: Anim.DefaultEffects } }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.iconText
                    color: Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                    grade: 25
                    fill: 1
                    visible: root.iconImageUrl === "" || pluginIconImage.status !== Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall
                    
                    StyledText {
                        text: root.titleText
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }
                    
                    StyledRect {
                        color: Qt.lighter(Colours.palette.m3surfaceVariant, 1.5)
                        radius: Tokens.rounding.small
                        implicitWidth: versionBadge.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: versionBadge.implicitHeight + Tokens.padding.extraSmall
                        Layout.alignment: Qt.AlignVCenter
                        
                        StyledText {
                            id: versionBadge

                            anchors.centerIn: parent
                            text: "v" + root.versionText
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.descriptionText
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                    wrapMode: root.isExpanded ? Text.Wrap : Text.NoWrap
                    maximumLineCount: root.isExpanded ? 10 : 1
                    visible: root.descriptionText !== ""
                }
            }

            Loader {
                active: !!root.actionComponent
                sourceComponent: root.actionComponent
                Layout.alignment: Qt.AlignVCenter
            }

            MaterialIcon {
                text: root.isExpanded ? "expand_less" : "expand_more"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        ColumnLayout {
            id: expandedContent
            Layout.fillWidth: true

            spacing: Tokens.spacing.large
            visible: root.isExpanded
            
            Item {
                id: mediaItem
                Layout.fillWidth: true
                Layout.preferredHeight: root.mediaUrl ? 220 : 0

                visible: true
                clip: true

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surface
                    opacity: 0.5
                    visible: !root.isTransparentMedia(root.mediaUrl)
                }

                AnimatedImage {
                    id: pluginImage

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    source: root.mediaUrl
                    visible: !root.isVideo(root.mediaUrl)
                    fillMode: Image.PreserveAspectFit
                    playing: visible
                }

                VideoOutput {
                    id: vidOut

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    visible: root.isVideo(root.mediaUrl)
                    fillMode: VideoOutput.PreserveAspectFit
                }
            }

            StyledRect {
                color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 1)
                radius: Tokens.rounding.small
                implicitWidth: authorText.implicitWidth + Tokens.padding.small * 2
                implicitHeight: authorText.implicitHeight + Tokens.padding.extraSmall
                visible: root.authorNameText !== ""

                StyledText {
                    id: authorText

                    anchors.centerIn: parent
                    text: root.authorNameText ? "by " + root.authorNameText : ""
                    font: Tokens.font.label.small
                    color: Colours.palette.m3primary
                }
            }

            AudioOutput {
                    id: aOut

                    muted: true
                }
                MediaPlayer {
                    id: mediaPlay

                    videoOutput: vidOut
                    audioOutput: aOut
                    source: root.isVideo(root.mediaUrl) ? root.mediaUrl : ""
                    loops: MediaPlayer.Infinite
                    
                    onSourceChanged: {
                        if (root.isVideo(root.mediaUrl) && root.isExpanded) play()
                        else pause()
                    }
                }
        }
    }
}
