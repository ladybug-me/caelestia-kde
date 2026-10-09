pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar.popouts as BarPopouts

StyledRect {
    id: root

    required property var popouts

    property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"

    implicitWidth: isHorizontal ? Tokens.sizes.bar.innerWidth : layout.implicitWidth
    implicitHeight: isHorizontal ? layout.implicitHeight : Tokens.sizes.bar.innerWidth

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, 0)
    radius: Tokens.rounding.full

    visible: enabled

    MouseArea {
        id: clickArea

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true

        onClicked: {
            if (mouse.button === Qt.LeftButton) {
                root.popouts.currentName = "screencapture";
                root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                root.popouts.hasCurrent = true;
            } else if (mouse.button === Qt.RightButton) {
                root.popouts.currentName = "screencapturecontext";
                root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                root.popouts.hasCurrent = true;
            }
            mouse.accepted = true;
        }

        onEntered: {
            if (Config.bar.showOnHover && !root.popouts.hasCurrent) {
                root.popouts.currentName = "screencapture";
                root.popouts.currentCenter = root.isHorizontal ? root.mapToItem(null, root.implicitWidth / 2, 0).x : (root.mapToItem(null, 0, root.implicitHeight / 2).y ?? 0);
                root.popouts.hasCurrent = true;
            }
        }

        onExited: {
            if (Config.bar.showOnHover && root.popouts.currentName === "screencapture" && !root.popouts.hasCurrent) {
                root.popouts.currentName = "";
                root.popouts.hasCurrent = false;
            }
        }
    }

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.medium

            IconButton {
                type: IconButton.Tonal
                isRound: true
                icon: Recorder.running ? "pause" : "screen_record"
                onClicked: {
                    if (Recorder.running) {
                        Recorder.togglePause();
                    } else {
                        Recorder.start();
                    }
                }
            }

            IconButton {
                type: IconButton.Tonal
                isRound: true
                icon: "screenshot_region"
                onClicked: {
                    Launch.exec(["qs", "-c", "caelestia", "ipc", "call", "region", "screenshot"]);
                }
            }

            IconButton {
                type: IconButton.Tonal
                isRound: true
                icon: "photo_camera"
                onClicked: {
                    const pad = n => String(n).padStart(2, "0");
                    const now = new Date();
                    const file = `${GlobalConfig.paths.screenshotsDir}/screenshot-${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}_${String(now.getHours()).padStart(2, "0")}.${String(now.getMinutes()).padStart(2, "0")}.${String(now.getSeconds()).padStart(2, "0")}.png`;
                    Launch.exec(["spectacle", "-b", "-f", "-o", file]);
                }
            }

            IconButton {
                type: IconButton.Tonal
                isRound: true
                icon: "video_camera_back"
                onClicked: {
                    Launch.exec(["spectacle", "-R", "s"]);
                }
            }

            IconButton {
                type: IconButton.Tonal
                isRound: true
                icon: "animated_images"
                onClicked: {
                    Recorder.startGif();
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.medium

            IconButton {
                type: IconButton.Tonal
                isRound: true
                icon: "animated_images"
                onClicked: {
                    Qt.openUrlExternally(`file://${GlobalConfig.paths.recordingsDir}`);
                }
            }

            IconButton {
                type: IconButton.Tonal
                isRound: true
                icon: "folder"
                onClicked: {
                    Qt.openUrlExternally(`file://${GlobalConfig.paths.screenshotsDir}`);
                }
            }

            IconButton {
                type: IconButton.Tonal
                isRound: true
                icon: "web"
                onClicked: {
                    Launch.exec(["spectacle"]);
                }
            }
        }
    }
}
