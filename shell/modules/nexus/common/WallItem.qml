pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    // The picker was handed the video file itself, which Image cannot decode, so
    // it sat at Image.Loading forever. Show the extracted frame instead — and
    // while it is being extracted, the spinner is honest rather than permanent.
    property string source
    readonly property bool isVideo: Images.isVideo(String(source).replace(/^file:\/\//, ""))
    readonly property string displaySource: root.isVideo ? Wallpapers.thumbFor(source) : source
    property alias text: label.text
    property alias radius: imgWrapper.radius
    property alias imgHeight: imgWrapper.implicitHeight
    property bool fillLabel: true
    property bool isFolder: false
    property int folderCount: 0

    signal clicked

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.small

        StyledClippingRect {
            id: imgWrapper

            Layout.fillWidth: true
            implicitHeight: width
            radius: Tokens.rounding.largeIncreased
            color: Colours.tPalette.m3surfaceContainer

            Loader {
                anchors.centerIn: parent

                opacity: img.status === Image.Ready ? 0 : 1
                active: opacity > 0

                sourceComponent: StyledRect {
                    implicitWidth: loadingIndicator.implicitSize + Tokens.padding.large * 2
                    implicitHeight: loadingIndicator.implicitSize + Tokens.padding.large * 2

                    color: Colours.palette.m3primaryContainer
                    radius: Tokens.rounding.full

                    LoadingIndicator {
                        id: loadingIndicator

                        anchors.centerIn: parent
                        containsIcon: true
                        implicitSize: Math.min(imgWrapper.width, imgWrapper.height) * 0.3
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            CachingImage {
                id: img

                path: root.displaySource
                anchors.fill: parent
                retainWhileLoading: true
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            StyledRect {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Tokens.padding.small
                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer
                visible: root.isFolder
                width: folderBadge.implicitWidth + Tokens.padding.medium * 2
                height: folderBadge.implicitHeight + Tokens.padding.small * 2

                RowLayout {
                    id: folderBadge

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "folder"
                        color: Colours.palette.m3onSecondaryContainer
                        fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                    }

                    StyledText {
                        text: root.folderCount > 0 ? String(root.folderCount) : ""
                        visible: root.folderCount > 0
                        color: Colours.palette.m3onSecondaryContainer
                        font: Tokens.font.label.builders.small.weight(Font.Medium).build()
                    }
                }
            }
        }

        StyledText {
            id: label

            Layout.bottomMargin: Tokens.padding.small
            Layout.fillWidth: true
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.builders.small.weight(Font.Medium).build()
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    StateLayer {
        anchors.bottomMargin: root.fillLabel ? 0 : layout.implicitHeight - imgWrapper.implicitHeight
        onClicked: root.clicked()
    }
}
